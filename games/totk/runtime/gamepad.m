/* Native macOS controllers feed the same FullKey state as the keyboard. */
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include "runtime.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static pthread_mutex_t gamepadLock = PTHREAD_MUTEX_INITIALIZER;
static RuntimeGamepadState gamepadState;
static uint64_t pressedEdges;
static BOOL started;

static int32_t stick_axis(float value) {
    const float deadzone = 0.12f;
    float magnitude = fabsf(value);
    if (magnitude <= deadzone) return 0;
    if (magnitude > 1.0f) magnitude = 1.0f;
    int32_t result = (int32_t)((magnitude - deadzone) / (1.0f - deadzone) * 32767.0f);
    return value < 0 ? -result : result;
}

static int32_t stronger_axis(int32_t a, int32_t b) {
    return abs(b) > abs(a) ? b : a;
}

static uint64_t gamepad_buttons(GCExtendedGamepad *pad) {
    uint64_t buttons = 0;
    if (pad.buttonA.isPressed) buttons |= 1ULL << 0;
    if (pad.buttonB.isPressed) buttons |= 1ULL << 1;
    if (pad.buttonX.isPressed) buttons |= 1ULL << 2;
    if (pad.buttonY.isPressed) buttons |= 1ULL << 3;
    if (pad.leftThumbstickButton.isPressed) buttons |= 1ULL << 4;
    if (pad.rightThumbstickButton.isPressed) buttons |= 1ULL << 5;
    if (pad.leftShoulder.isPressed) buttons |= 1ULL << 6;
    if (pad.rightShoulder.isPressed) buttons |= 1ULL << 7;
    if (pad.leftTrigger.isPressed) buttons |= 1ULL << 8;
    if (pad.rightTrigger.isPressed) buttons |= 1ULL << 9;
    if (pad.buttonMenu.isPressed) buttons |= 1ULL << 10;
    if (pad.buttonOptions.isPressed) buttons |= 1ULL << 11;
    if (pad.dpad.left.isPressed) buttons |= 1ULL << 12;
    if (pad.dpad.up.isPressed) buttons |= 1ULL << 13;
    if (pad.dpad.right.isPressed) buttons |= 1ULL << 14;
    if (pad.dpad.down.isPressed) buttons |= 1ULL << 15;
    return buttons;
}

/* pro-bridge (~/htdocs/pro-bridge, DSU on 127.0.0.1:26760) reads the Switch Pro Controller through SDL3. Over Bluetooth, macOS
   GameController never reports that controller's left stick (it arrives as a D-pad), so while DSU slot 0 is live its left
   stick and D-pad replace the GameController ones. */
static _Atomic int32_t dsuLx, dsuLy;
static _Atomic uint32_t dsuDpad;
static _Atomic uint64_t dsuSeenMs;
static uint64_t now_ms(void) { struct timeval tv; gettimeofday(&tv, NULL); return (uint64_t)tv.tv_sec * 1000 + (uint64_t)tv.tv_usec / 1000; }
static int32_t dsu_axis(uint8_t v) { return stick_axis(((float)v - 128.0f) / 127.0f); }
static void *dsu_thread(void *unused) {
    (void)unused;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) return NULL;
    struct timeval timeout = {0, 500000};
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);
    struct sockaddr_in server = {0};
    server.sin_family = AF_INET; server.sin_port = htons(26760); server.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    uint8_t request[28] = {0}, packet[128];
    memcpy(request, "DSUC", 4);
    uint16_t version = 1001, length = 12; uint32_t type = 0x100002, client = 0x544f544b;
    memcpy(request + 4, &version, 2); memcpy(request + 6, &length, 2); memcpy(request + 12, &client, 4); memcpy(request + 16, &type, 4);
    request[20] = 1; request[21] = 0;   /* subscribe by slot: slot 0 */
    uint64_t lastRequest = 0; int announced = 0;
    for (;;) {
        uint64_t now = now_ms();
        if (now - lastRequest >= 1000) { sendto(s, request, sizeof request, 0, (struct sockaddr *)&server, sizeof server); lastRequest = now; }
        ssize_t n = recv(s, packet, sizeof packet, 0);
        if (n < 44 || memcmp(packet, "DSUS", 4)) continue;
        uint32_t message; memcpy(&message, packet + 16, 4);
        if (message != 0x100002 || packet[20] != 0 || packet[21] != 2) continue;
        uint8_t b = packet[36];
        atomic_store(&dsuDpad, (b & 0x80 ? 1u << 12 : 0) | (b & 0x10 ? 1u << 13 : 0) | (b & 0x20 ? 1u << 14 : 0) | (b & 0x40 ? 1u << 15 : 0));
        atomic_store(&dsuLx, dsu_axis(packet[40])); atomic_store(&dsuLy, dsu_axis(packet[41]));
        atomic_store(&dsuSeenMs, now_ms());
        if (!announced) { announced = 1; fprintf(stderr, "[totk-input] pro-bridge DSU slot 0 live: left stick and D-pad from SDL3\n"); }
    }
    return NULL;
}

static void refresh_gamepads(void) {
    RuntimeGamepadState next = {0};
    for (GCController *controller in GCController.controllers) {
        GCExtendedGamepad *pad = controller.extendedGamepad;
        if (!pad) continue;
        next.connected = 1;
        next.buttons |= gamepad_buttons(pad);
        next.lx = stronger_axis(next.lx, stick_axis(pad.leftThumbstick.xAxis.value));
        next.ly = stronger_axis(next.ly, stick_axis(pad.leftThumbstick.yAxis.value));
        next.rx = stronger_axis(next.rx, stick_axis(pad.rightThumbstick.xAxis.value));
        next.ry = stronger_axis(next.ry, stick_axis(pad.rightThumbstick.yAxis.value));
    }
    pthread_mutex_lock(&gamepadLock);
    pressedEdges |= next.buttons & ~gamepadState.buttons;
    gamepadState = next;
    pthread_mutex_unlock(&gamepadLock);
}

static void attach_gamepad(GCController *controller) {
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (!pad) return;
    pad.valueChangedHandler = ^(GCExtendedGamepad *changed, GCControllerElement *element) {
        (void)changed; (void)element;
        refresh_gamepads();
    };
    fprintf(stderr, "[totk-input] native gamepad connected: %s (%s)\n",
            (controller.vendorName ?: @"unknown").UTF8String,
            (controller.productCategory ?: @"unknown").UTF8String);
    runtime_feedback_attach(controller);
    refresh_gamepads();
}

void runtime_gamepad_start(void) {
    if (started) return;
    started = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue
                   usingBlock:^(NSNotification *notification) { attach_gamepad(notification.object); }];
    [center addObserverForName:GCControllerDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue
                   usingBlock:^(NSNotification *notification) {
                       GCController *controller = notification.object;
                       fprintf(stderr, "[totk-input] native gamepad disconnected: %s\n",
                               (controller.vendorName ?: @"unknown").UTF8String);
                       runtime_feedback_detach(controller);
                       refresh_gamepads();
                   }];
    for (GCController *controller in GCController.controllers) attach_gamepad(controller);
    [GCController startWirelessControllerDiscoveryWithCompletionHandler:nil];
    pthread_t dsu; if (!pthread_create(&dsu, NULL, dsu_thread, NULL)) pthread_detach(dsu);
}

void runtime_gamepad_clear(void) {
    runtime_feedback_quiet();
    pthread_mutex_lock(&gamepadLock);
    gamepadState = (RuntimeGamepadState){0};
    pressedEdges = 0;
    pthread_mutex_unlock(&gamepadLock);
}

/* On-screen touch controls (iPhone, ios/app/Sources/touch_controls.m) feed a second state merged with the physical
   controllers: buttons are OR-ed (a tap shorter than one game frame is latched like a controller press), each stick
   axis takes the stronger value. */
static RuntimeGamepadState touchState;
void runtime_touch_pad_set(const RuntimeGamepadState *s) {
    pthread_mutex_lock(&gamepadLock);
    pressedEdges |= s->buttons & ~touchState.buttons;
    touchState = *s;
    pthread_mutex_unlock(&gamepadLock);
}

void runtime_gamepad_read(RuntimeGamepadState *out) {
    pthread_mutex_lock(&gamepadLock);
    *out = gamepadState;
    out->buttons |= touchState.buttons | pressedEdges;
    if (now_ms() - atomic_load(&dsuSeenMs) < 300) {
        out->connected = 1;
        out->buttons = (out->buttons & ~(0xfULL << 12)) | atomic_load(&dsuDpad);
        out->lx = stronger_axis(out->lx, atomic_load(&dsuLx)); out->ly = stronger_axis(out->ly, atomic_load(&dsuLy));
    }
    out->lx = stronger_axis(out->lx, touchState.lx); out->ly = stronger_axis(out->ly, touchState.ly);
    out->rx = stronger_axis(out->rx, touchState.rx); out->ry = stronger_axis(out->ry, touchState.ry);
    if (touchState.connected) out->connected = 1;
    pressedEdges = 0;
    pthread_mutex_unlock(&gamepadLock);
}
