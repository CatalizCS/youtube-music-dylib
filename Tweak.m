#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import "DiscordRPCManager.h"
#import "SettingsViewController.h"

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
    double rate = [nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] doubleValue];
    
    BOOL isPlaying = (rate > 0.0);
    NSString *videoID = getCurrentVideoID();
    
    NSLog(@"[DiscordRPC] Captured setNowPlayingInfo. Title: %@, Artist: %@, Duration: %f, Elapsed: %f, Rate: %f, VideoID: %@", 
          title, artist, duration, elapsed, rate, videoID);
          
    [[DiscordRPCManager sharedManager] updatePresenceWithTitle:title
                                                        artist:artist
                                                         album:album
                                                      duration:duration
                                                   elapsedTime:elapsed
                                                     isPlaying:isPlaying
                                                       videoID:videoID];
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
    
    // Auto-connect on start if RPC is enabled
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:@"DiscordRPCEnabled"];
    if (enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[DiscordRPCManager sharedManager] connect];
        });
    }
    
    NSLog(@"[DiscordRPC] Dylib loaded and swizzled successfully.");
}
