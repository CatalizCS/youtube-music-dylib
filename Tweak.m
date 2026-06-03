#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "DiscordRPCManager.h"
#import "SettingsViewController.h"

// Redefine NSLog to log to both system console and file
#define NSLog(format, ...) RPCLog(format, ##__VA_ARGS__)

// Forward declarations of classes
@interface YTPlayerViewController : UIViewController
- (NSString *)currentVideoID;
@end

@interface YTMAccountButton : UIButton
- (id)initWithTitle:(id)title identifier:(id)identifier icon:(id)icon actionBlock:(void (^)(BOOL finished))actionBlock;
@end

@interface UIView (PrivateAncestor)
- (UIViewController *)_viewControllerForAncestor;
@end

// Static pointer to track active YTPlayerViewController
static __weak YTPlayerViewController *activePlayerViewController = nil;

static NSString *getCurrentVideoID() {
    if (activePlayerViewController) {
        if ([activePlayerViewController respondsToSelector:@selector(currentVideoID)]) {
            return [activePlayerViewController currentVideoID];
        }
    }
    return nil;
}

// Helper function to perform method swizzling
static void swizzleMethod(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    
    BOOL didAddMethod = class_addMethod(class,
                                        originalSelector,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(class,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

// --- Hook implementations using Categories ---

@implementation UIViewController (YTPlayerViewControllerHook)

- (void)custom_viewDidAppear:(BOOL)animated {
    // Execute original viewDidAppear
    [self custom_viewDidAppear:animated];
    
    // Check class name dynamically
    if ([self isKindOfClass:NSClassFromString(@"YTPlayerViewController")]) {
        activePlayerViewController = (YTPlayerViewController *)self;
        NSLog(@"[DiscordRPC] Active YTPlayerViewController captured: %@", activePlayerViewController);
    }
}

@end

@implementation NSObject (MPNowPlayingInfoCenterHook)

- (void)custom_setNowPlayingInfo:(NSDictionary *)nowPlayingInfo {
    // Execute original setNowPlayingInfo
    [self custom_setNowPlayingInfo:nowPlayingInfo];
    
    if (!nowPlayingInfo) {
        return;
    }
    
    NSString *title = nowPlayingInfo[MPMediaItemPropertyTitle];
    NSString *artist = nowPlayingInfo[MPMediaItemPropertyArtist];
    NSString *album = nowPlayingInfo[MPMediaItemPropertyAlbumTitle];
    
    double duration = [nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] doubleValue];
    double elapsed = [nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
    
    BOOL isPlaying = NO;
    MPNowPlayingInfoCenter *center = (MPNowPlayingInfoCenter *)self;
    if ([center respondsToSelector:@selector(playbackState)]) {
        isPlaying = (center.playbackState == MPNowPlayingPlaybackStatePlaying);
    } else {
        double rate = [nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] doubleValue];
        isPlaying = (rate > 0.0);
    }
    
    NSString *videoID = getCurrentVideoID();
    
    NSLog(@"[DiscordRPC] Captured setNowPlayingInfo. Title: %@, Artist: %@, Duration: %f, Elapsed: %f, isPlaying: %d, VideoID: %@", 
          title, artist, duration, elapsed, isPlaying, videoID);
          
    [[DiscordRPCManager sharedManager] updatePresenceWithTitle:title
                                                        artist:artist
                                                         album:album
                                                       duration:duration
                                                    elapsedTime:elapsed
                                                      isPlaying:isPlaying
                                                        videoID:videoID];
}

@end

@implementation NSObject (MPNowPlayingInfoCenterPlaybackStateHook)

- (void)custom_setPlaybackState:(MPNowPlayingPlaybackState)playbackState {
    // Execute original setPlaybackState
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    SEL swizSel = NSSelectorFromString(@"custom_setPlaybackState:");
    if ([self respondsToSelector:swizSel]) {
        void (*orig)(id, SEL, MPNowPlayingPlaybackState) = (void *)[self methodForSelector:swizSel];
        orig(self, swizSel, playbackState);
    }
    #pragma clang diagnostic pop

    BOOL isPlaying = (playbackState == MPNowPlayingPlaybackStatePlaying);
    NSLog(@"[DiscordRPC] Captured setPlaybackState: %ld (isPlaying: %d)", (long)playbackState, isPlaying);

    MPNowPlayingInfoCenter *center = (MPNowPlayingInfoCenter *)self;
    NSDictionary *nowPlayingInfo = center.nowPlayingInfo;
    if (nowPlayingInfo) {
        NSString *title = nowPlayingInfo[MPMediaItemPropertyTitle];
        NSString *artist = nowPlayingInfo[MPMediaItemPropertyArtist];
        NSString *album = nowPlayingInfo[MPMediaItemPropertyAlbumTitle];
        
        double duration = [nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] doubleValue];
        double elapsed = [nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
        NSString *videoID = getCurrentVideoID();
        
        [[DiscordRPCManager sharedManager] updatePresenceWithTitle:title
                                                            artist:artist
                                                             album:album
                                                           duration:duration
                                                        elapsedTime:elapsed
                                                          isPlaying:isPlaying
                                                            videoID:videoID];
    }
}

@end

@implementation UIView (YTMAvatarAccountViewHook)

- (void)custom_setAccountMenuUpperButtons:(id)arg1 lowerButtons:(id)arg2 {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
    UIImage *icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        // Use standard iOS system network/bolt icon for RPC settings
        UIImage *rpcSymbol = [UIImage systemImageNamed:@"network"];
        UIImageView *rpcImageView = [[UIImageView alloc] initWithImage:rpcSymbol];
        rpcImageView.contentMode = UIViewContentModeScaleAspectFit;
        rpcImageView.clipsToBounds = YES;
        rpcImageView.tintColor = [UIColor redColor];
        rpcImageView.frame = CGRectMake(0, 0, 24, 24);
        [rpcImageView.layer renderInContext:rendererContext.CGContext];
    }];

    Class buttonClass = NSClassFromString(@"YTMAccountButton");
    YTMAccountButton *button = [[buttonClass alloc] initWithTitle:@"Discord RPC" 
                                                                identifier:@"discord_rpc_settings" 
                                                                      icon:icon 
                                                               actionBlock:^(BOOL finished) {
        SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        [nav setModalPresentationStyle:UIModalPresentationFullScreen];
        
        UIViewController *parentVC = nil;
        if ([self respondsToSelector:@selector(_viewControllerForAncestor)]) {
            parentVC = [self _viewControllerForAncestor];
        }
        if (parentVC) {
            [parentVC presentViewController:nav animated:YES completion:nil];
        }
    }];

    button.tintColor = [UIColor redColor];

    NSMutableArray *arrDown = [[NSMutableArray alloc] init];
    [arrDown addObjectsFromArray:arg2];
    [arrDown addObject:button];

    // Execute original setAccountMenuUpperButtons:lowerButtons:
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [self performSelector:NSSelectorFromString(@"custom_setAccountMenuUpperButtons:lowerButtons:")
               withObject:arg1
               withObject:arrDown];
    #pragma clang diagnostic pop
}

@end

static void showStartupActivityPicker() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:@"DiscordRPCEnabled"];
    if (!enabled) return;
    
    // Check if quick select is enabled (defaults to YES)
    if ([defaults objectForKey:@"DiscordRPCQuickSelectOnStartup"] != nil) {
        if (![defaults boolForKey:@"DiscordRPCQuickSelectOnStartup"]) {
            return;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *window in windowScene.windows) {
                        if (window.isKeyWindow) {
                            keyWindow = window;
                            break;
                        }
                    }
                }
                if (keyWindow) break;
            }
        }
        if (!keyWindow) {
            keyWindow = [UIApplication sharedApplication].keyWindow;
        }
        
        UIViewController *rootVC = keyWindow.rootViewController;
        if (!rootVC) return;
        
        // Find top view controller
        UIViewController *topVC = rootVC;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Discord RPC"
                                                                       message:@"Chọn nhanh hoạt động của bạn:"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
                                                                
        NSArray *options = @[
            @"🎵 Normal (Chỉ nghe nhạc)",
            @"🚗 Commuting (Đang đi đường)",
            @"🏃 Jogging (Đang chạy bộ)",
            @"💤 Chilling (Đang thư giãn)",
            @"📚 Studying (Đang học bài)",
            @"🎮 Gaming (Đang chơi game)",
            @"🏋️ Working Out (Đang tập thể dục)"
        ];
        
        for (NSInteger i = 0; i < options.count; i++) {
            NSString *option = options[i];
            [alert addAction:[UIAlertAction actionWithTitle:option
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction * _Nonnull action) {
                [defaults setInteger:i forKey:@"DiscordRPCActivityStatus"];
                [defaults synchronize];
                NSLog(@"[DiscordRPC] Startup activity set to: %ld", (long)i);
                
                if ([DiscordRPCManager sharedManager].isConnected) {
                    [[DiscordRPCManager sharedManager] sendPresenceUpdate];
                } else {
                    [[DiscordRPCManager sharedManager] connect];
                }
            }]];
        }
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
                                                
        // Handle iPad popover
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            alert.popoverPresentationController.sourceView = topVC.view;
            alert.popoverPresentationController.sourceRect = CGRectMake(topVC.view.bounds.size.width / 2.0, topVC.view.bounds.size.height / 2.0, 1.0, 1.0);
            alert.popoverPresentationController.permittedArrowDirections = 0;
        }
        
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

// Constructor function run on dylib load
__attribute__((constructor)) static void init() {
    NSLog(@"[DiscordRPC] Loading dylib...");
    
    // Swizzle YTPlayerViewController viewDidAppear:
    Class ytpVCClass = NSClassFromString(@"YTPlayerViewController");
    if (ytpVCClass) {
        SEL origSel = @selector(viewDidAppear:);
        SEL swizSel = @selector(custom_viewDidAppear:);
        
        Method customMethod = class_getInstanceMethod([UIViewController class], swizSel);
        class_addMethod(ytpVCClass,
                        swizSel,
                        method_getImplementation(customMethod),
                        method_getTypeEncoding(customMethod));
                        
        swizzleMethod(ytpVCClass, origSel, swizSel);
        NSLog(@"[DiscordRPC] Swizzled YTPlayerViewController viewDidAppear:");
    }
    
    // Swizzle MPNowPlayingInfoCenter setNowPlayingInfo:
    Class mpClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (mpClass) {
        SEL origSel = @selector(setNowPlayingInfo:);
        SEL swizSel = @selector(custom_setNowPlayingInfo:);
        
        Method customMethod = class_getInstanceMethod([NSObject class], swizSel);
        class_addMethod(mpClass,
                        swizSel,
                        method_getImplementation(customMethod),
                        method_getTypeEncoding(customMethod));
                        
        swizzleMethod(mpClass, origSel, swizSel);
        NSLog(@"[DiscordRPC] Swizzled MPNowPlayingInfoCenter setNowPlayingInfo:");
    }
    
    // Swizzle MPNowPlayingInfoCenter setPlaybackState:
    if (mpClass && [mpClass instancesRespondToSelector:NSSelectorFromString(@"setPlaybackState:")]) {
        SEL origSel = NSSelectorFromString(@"setPlaybackState:");
        SEL swizSel = @selector(custom_setPlaybackState:);
        
        Method customMethod = class_getInstanceMethod([NSObject class], swizSel);
        class_addMethod(mpClass,
                        swizSel,
                        method_getImplementation(customMethod),
                        method_getTypeEncoding(customMethod));
                        
        swizzleMethod(mpClass, origSel, swizSel);
        NSLog(@"[DiscordRPC] Swizzled MPNowPlayingInfoCenter setPlaybackState:");
    }
    
    // Swizzle YTMAvatarAccountView setAccountMenuUpperButtons:lowerButtons:
    Class avatarViewClass = NSClassFromString(@"YTMAvatarAccountView");
    if (avatarViewClass) {
        SEL origSel = NSSelectorFromString(@"setAccountMenuUpperButtons:lowerButtons:");
        SEL swizSel = @selector(custom_setAccountMenuUpperButtons:lowerButtons:);
        
        Method customMethod = class_getInstanceMethod([UIView class], swizSel);
        class_addMethod(avatarViewClass,
                        swizSel,
                        method_getImplementation(customMethod),
                        method_getTypeEncoding(customMethod));
                        
        swizzleMethod(avatarViewClass, origSel, swizSel);
        NSLog(@"[DiscordRPC] Swizzled YTMAvatarAccountView setAccountMenuUpperButtons:lowerButtons:");
    }
    
    // Auto-connect on start if RPC is enabled and show startup picker
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:@"DiscordRPCEnabled"];
    if (enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[DiscordRPCManager sharedManager] connect];
            
            if ([UIApplication sharedApplication].keyWindow) {
                showStartupActivityPicker();
            } else {
                __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                                  object:nil
                                                                   queue:[NSOperationQueue mainQueue]
                                                              usingBlock:^(NSNotification * _Nonnull note) {
                    showStartupActivityPicker();
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                }];
            }
        });
    }
    
    NSLog(@"[DiscordRPC] Dylib loaded and swizzled successfully.");
}
