// WaveToSilence 1.0.0 — vẫy tay qua cảm biến tiệm cận để TẮT CHUÔNG cuộc
// gọi đến (Phone + mọi app gọi qua CallKit: Messenger, Zalo, WhatsApp...).
// Chỉ tắt tiếng, KHÔNG cúp máy — cuộc gọi vẫn đổ tiếp trên màn hình.
//
// Ba khâu, mỗi khâu đều ghi log chẩn đoán để test máy thật soi được ngay
// khâu nào chạy, khâu nào chưa (bài học từ Raise2Answer):
//  1) Phát hiện cuộc gọi: CXCallObserver của CallKit (API công khai) —
//     thấy cả cuộc gọi SIM lẫn VoIP CallKit. Tweak này không dùng %hook nào.
//  2) Cảm biến tiệm cận: hỏi vòng mỗi 100ms CHỈ trong lúc đang đổ chuông.
//     Nguồn A: UIDevice.proximityState. Nguồn B: SBProximitySensorManager
//     (dò selector lúc chạy). Chỉ tính là "vẫy" khi cảm biến chuyển từ
//     trống → bị che, và phải từng thấy trạng thái trống sau khi chuông
//     bắt đầu (máy trong túi/úp mặt sẵn thì không tắt nhầm).
//  3) Tắt chuông: hạ âm lượng nhóm "Ringtone" về 0 qua AVSystemController
//     (đường chính); dự phòng dò các selector tắt chuông trên TUCall.
//     Cuộc gọi kết thúc/được nghe máy thì trả lại âm lượng chuông cũ.
#import <UIKit/UIKit.h>
#import <CallKit/CXCallObserver.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const WS_DOMAIN = @"com.vn.wavetosilence";
static NSString *const WS_PREFS_NOTIFICATION = @"com.vn.wavetosilence/prefsChanged";
static NSString *const WS_LOG_PATH = @"/var/mobile/Documents/WaveToSilence.log";

static BOOL pEnabled    = YES;
static BOOL pDoubleWave = NO;
static BOOL pDebug      = YES;

// ---------------------------------------------------------------- log
static void WSLog(NSString *fmt, ...) {
    if (!pDebug) return;
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[WaveToSilence] %@", msg);
    @try {
        NSString *line = [NSString stringWithFormat:@"%@ %@\n",
                          [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                         dateStyle:NSDateFormatterNoStyle
                                                         timeStyle:NSDateFormatterMediumStyle],
                          msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:WS_LOG_PATH];
        if (!fh) {
            [line writeToFile:WS_LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (__unused NSException *e) {}
}

// ---------------------------------------------------------------- prefs
static id WSGetPref(NSString *key, id def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)WS_DOMAIN);
    id obj = (__bridge_transfer id)v;
    return obj ?: def;
}

static void WSLoadPrefs(void) {
    pEnabled    = [WSGetPref(@"enabled",    @YES) boolValue];
    pDoubleWave = [WSGetPref(@"doubleWave", @NO)  boolValue];
    pDebug      = [WSGetPref(@"debug",      @YES) boolValue];
}

// ---------------------------------------------------------------- msgSend helpers
static id WSMsg(id obj, SEL sel) {
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
static BOOL WSMsgBool(id obj, SEL sel) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
}

// ---------------------------------------------------------------- khâu 3: tắt chuông
static BOOL  gSilenced    = NO;
static float gSavedVolume = -1.0f;

static id WSAudioController(void) {
    Class c = NSClassFromString(@"AVSystemController");
    if (!c || ![c respondsToSelector:@selector(sharedAVSystemController)]) return nil;
    return WSMsg(c, @selector(sharedAVSystemController));
}

static BOOL WSGetRingtoneVolume(float *out) {
    id av = WSAudioController();
    SEL sel = NSSelectorFromString(@"getVolume:forCategory:");
    if (!av || ![av respondsToSelector:sel]) return NO;
    return ((BOOL (*)(id, SEL, float *, id))objc_msgSend)(av, sel, out, @"Ringtone");
}

static BOOL WSSetRingtoneVolume(float v) {
    id av = WSAudioController();
    SEL sel = NSSelectorFromString(@"setVolumeTo:forCategory:");
    if (!av || ![av respondsToSelector:sel]) return NO;
    return ((BOOL (*)(id, SEL, float, id))objc_msgSend)(av, sel, v, @"Ringtone");
}

// Dự phòng: dò TUCallCenter -> cuộc gọi hiện tại -> các selector tắt chuông
// quen thuộc. Trả YES nếu có một selector tồn tại và đã gọi.
static BOOL WSSilenceViaTUCall(void) {
    @try {
        Class cc = NSClassFromString(@"TUCallCenter");
        if (!cc || ![cc respondsToSelector:@selector(sharedInstance)]) return NO;
        id center = WSMsg(cc, @selector(sharedInstance));
        if (!center) return NO;
        id call = nil;
        for (NSString *name in @[@"currentCall", @"incomingCall", @"frontmostCall"]) {
            SEL sel = NSSelectorFromString(name);
            if ([center respondsToSelector:sel]) { call = WSMsg(center, sel); if (call) break; }
        }
        if (!call) { WSLog(@"TUCall du phong: khong thay cuoc goi hien tai"); return NO; }
        for (NSString *name in @[@"silenceRingtone", @"stopRingtone", @"stopRinging",
                                 @"muteRingtone", @"silence"]) {
            SEL sel = NSSelectorFromString(name);
            if ([call respondsToSelector:sel]) {
                WSMsg(call, sel);
                WSLog(@"Silence qua TUCall.%@", name);
                return YES;
            }
        }
        WSLog(@"TUCall du phong: khong selector tat chuong nao ton tai");
    } @catch (__unused NSException *e) {}
    return NO;
}

static void WSSilenceRing(void) {
    if (gSilenced) return;
    float cur = -1.0f;
    if (WSGetRingtoneVolume(&cur)) {
        gSavedVolume = cur;
        if (WSSetRingtoneVolume(0.0f)) {
            gSilenced = YES;
            WSLog(@"Da tat chuong: Ringtone %.2f -> 0", (double)cur);
            return;
        }
        WSLog(@"Tat chuong THAT BAI: setVolumeTo:forCategory: tra ve NO");
    } else {
        WSLog(@"AVSystemController khong dung duoc — thu duong TUCall");
    }
    if (WSSilenceViaTUCall()) {
        gSilenced = YES;
        gSavedVolume = -1.0f; // tắt qua TUCall thì không có âm lượng để trả
    } else {
        WSLog(@"Tat chuong THAT BAI o tat ca cac duong");
    }
}

static void WSRestoreVolume(void) {
    if (!gSilenced) return;
    gSilenced = NO;
    if (gSavedVolume < 0) { WSLog(@"Khong can tra am luong (da tat qua TUCall)"); return; }
    float cur = -1.0f;
    if (WSGetRingtoneVolume(&cur) && cur < 0.01f) {
        WSSetRingtoneVolume(gSavedVolume);
        WSLog(@"Da tra am luong chuong -> %.2f", (double)gSavedVolume);
    } else {
        WSLog(@"Khong tra am luong: hien tai %.2f (nguoi dung da tu chinh?)", (double)cur);
    }
    gSavedVolume = -1.0f;
}

// ---------------------------------------------------------------- quản lý cuộc gọi + cảm biến
@interface WSCallManager : NSObject <CXCallObserverDelegate>
+ (instancetype)shared;
- (void)start;
- (void)reloadPrefs;
- (void)evaluateCalls;
- (void)startWatching;
- (void)stopWatchingAndRestore;
- (void)pollTick;
- (void)handleWave;
- (BOOL)sbManagerNear;
@end

@implementation WSCallManager {
    CXCallObserver *_observer;
    NSTimer *_pollTimer;
    BOOL _watching;
    BOOL _sawFar;
    BOOL _prevNear;
    NSUInteger _waveCount;
    NSTimeInterval _firstWaveAt;
    id _sbManager;
    NSString *_sbNearSelName;
    BOOL _loggedSBNoSel;
}

+ (instancetype)shared {
    static WSCallManager *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [WSCallManager new]; });
    return inst;
}

- (void)start {
    _observer = [CXCallObserver new];
    [_observer setDelegate:self queue:dispatch_get_main_queue()];
    WSLog(@"WaveToSilence 1.0.0 loaded. enabled=%d CXCallObserver=%@ AVSystemController=%@ SBProximitySensorManager=%@",
          pEnabled,
          NSClassFromString(@"CXCallObserver") ? @"co" : @"KHONG",
          NSClassFromString(@"AVSystemController") ? @"co" : @"KHONG",
          NSClassFromString(@"SBProximitySensorManager") ? @"co" : @"KHONG");
    [self evaluateCalls];
}

- (void)reloadPrefs {
    WSLoadPrefs();
    WSLog(@"Prefs reloaded. enabled=%d doubleWave=%d", pEnabled, pDoubleWave);
    if (!pEnabled) [self stopWatchingAndRestore];
    else [self evaluateCalls];
}

- (void)callObserver:(CXCallObserver *)callObserver callChanged:(CXCall *)call {
    WSLog(@"callChanged: outgoing=%d connected=%d ended=%d",
          call.outgoing, call.hasConnected, call.hasEnded);
    [self evaluateCalls];
}

- (void)evaluateCalls {
    BOOL ringing = NO;
    for (CXCall *call in _observer.calls) {
        if (!call.outgoing && !call.hasConnected && !call.hasEnded) { ringing = YES; break; }
    }
    if (ringing && pEnabled) [self startWatching];
    else if (!ringing) [self stopWatchingAndRestore];
}

- (void)startWatching {
    if (_watching) return;
    _watching = YES;
    _sawFar = NO;
    _prevNear = NO;
    _waveCount = 0;
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;

    // Nguồn B: SBProximitySensorManager — lấy instance và thử bật dò.
    @try {
        Class mc = NSClassFromString(@"SBProximitySensorManager");
        if (mc) {
            for (NSString *name in @[@"sharedManager", @"sharedInstance", @"defaultManager"]) {
                SEL sel = NSSelectorFromString(name);
                if ([mc respondsToSelector:sel]) { _sbManager = WSMsg(mc, sel); if (_sbManager) break; }
            }
            if (_sbManager) {
                SEL en = NSSelectorFromString(@"enableProximityDetection");
                if ([_sbManager respondsToSelector:en]) WSMsg(_sbManager, en);
                SEL setEn = NSSelectorFromString(@"setProximityDetectionEnabled:");
                if ([_sbManager respondsToSelector:setEn])
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(_sbManager, setEn, YES);
            }
        }
    } @catch (__unused NSException *e) { _sbManager = nil; }

    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                  target:self
                                                selector:@selector(pollTick)
                                                userInfo:nil
                                                 repeats:YES];
    WSLog(@"Dang do chuong -> bat dau theo doi tiem can (SB manager: %@)", _sbManager ? @"co" : @"khong");
}

- (void)stopWatchingAndRestore {
    if (_watching) {
        _watching = NO;
        [_pollTimer invalidate];
        _pollTimer = nil;
        [UIDevice currentDevice].proximityMonitoringEnabled = NO;
        @try {
            SEL dis = NSSelectorFromString(@"disableProximityDetection");
            if (_sbManager && [_sbManager respondsToSelector:dis]) WSMsg(_sbManager, dis);
        } @catch (__unused NSException *e) {}
        WSLog(@"Cuoc goi ket thuc/da nghe -> dung theo doi tiem can");
    }
    WSRestoreVolume();
}

// Trạng thái "có vật gần" từ SBProximitySensorManager — dò lần lượt các
// getter quen thuộc, dùng cái đầu tiên tồn tại.
- (BOOL)sbManagerNear {
    if (!_sbManager) return NO;
    if (!_sbNearSelName) {
        for (NSString *name in @[@"isObjectInProximity", @"objectInProximity",
                                 @"proximityState", @"isNear"]) {
            if ([_sbManager respondsToSelector:NSSelectorFromString(name)]) {
                _sbNearSelName = name;
                WSLog(@"SBProximitySensorManager: dung getter %@", name);
                break;
            }
        }
        if (!_sbNearSelName && !_loggedSBNoSel) {
            _loggedSBNoSel = YES;
            WSLog(@"SBProximitySensorManager: khong getter trang thai nao ton tai");
        }
    }
    if (!_sbNearSelName) return NO;
    @try {
        return WSMsgBool(_sbManager, NSSelectorFromString(_sbNearSelName));
    } @catch (__unused NSException *e) {}
    return NO;
}

- (void)pollTick {
    if (!_watching) return;
    BOOL near = NO;
    NSString *src = nil;
    UIDevice *dev = [UIDevice currentDevice];
    if (dev.proximityMonitoringEnabled && dev.proximityState) { near = YES; src = @"UIDevice"; }
    if (!near && [self sbManagerNear]) { near = YES; src = @"SBProximitySensorManager"; }

    if (!near) _sawFar = YES;
    if (near && !_prevNear) { // cạnh lên: một cú vẫy vừa che cảm biến
        WSLog(@"Phat hien vay tay (nguon: %@)", src ?: @"?");
        if (!_sawFar) {
            WSLog(@"Bo qua: cam bien da bi che san tu truoc khi do chuong (tui/up mat?)");
        } else {
            [self handleWave];
        }
    }
    _prevNear = near;
}

- (void)handleWave {
    if (gSilenced) return;
    if (!pDoubleWave) { WSSilenceRing(); return; }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (_waveCount == 1 && (now - _firstWaveAt) <= 1.5) {
        _waveCount = 0;
        WSLog(@"Vay lan 2 — tat chuong");
        WSSilenceRing();
    } else {
        _waveCount = 1;
        _firstWaveAt = now;
        WSLog(@"Vay lan 1/2 — cho vay lan 2 trong 1,5 giay");
    }
}

@end

// ---------------------------------------------------------------- ctor
static void WSPrefsChanged(CFNotificationCenterRef center, void *observer,
                           CFStringRef name, const void *object,
                           CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WSCallManager shared] reloadPrefs];
    });
}

%ctor {
    @autoreleasepool {
        WSLoadPrefs();
        [[WSCallManager shared] start];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WSPrefsChanged, (__bridge CFStringRef)WS_PREFS_NOTIFICATION, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
