#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "DiscordRPCManager.h"
#import "SettingsViewController.h"

// Interface declarations for internal YTM classes
@interface YTPlayerViewController : UIViewController
- (NSString *)currentVideoID;
@end

@interface YTMAccountButton : UIButton
- (id)initWithTitle:(id)title identifier:(id)identifier icon:(id)icon actionBlock:(void (^)(BOOL finished))actionBlock;
@end

@interface YTMAvatarAccountView : UIView
@end

@interface UIView (Private)
- (id)_viewControllerForAncestor;
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

// Hook into YTPlayerViewController to capture the active instance
%hook YTPlayerViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    activePlayerViewController = self;
    NSLog(@"[DiscordRPC] Active YTPlayerViewController captured: %@", activePlayerViewController);
}

%end

// Hook into MPNowPlayingInfoCenter to capture media updates
%hook MPNowPlayingInfoCenter

- (void)setNowPlayingInfo:(NSDictionary *)nowPlayingInfo {
    %orig;
    
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

%end

// Hook into the account view to inject our settings menu option
%hook YTMAvatarAccountView

- (void)setAccountMenuUpperButtons:(id)arg1 lowerButtons:(id)arg2 {
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

    YTMAccountButton *button = [[%c(YTMAccountButton) alloc] initWithTitle:@"Discord RPC" 
                                                                identifier:@"discord_rpc_settings" 
                                                                      icon:icon 
                                                               actionBlock:^(BOOL finished) {
        SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
        [nav setModalPresentationStyle:UIModalPresentationFullScreen];
        
        UIViewController *parentVC = [self _viewControllerForAncestor];
        if (parentVC) {
            [parentVC presentViewController:nav animated:YES completion:nil];
        }
    }];

    button.tintColor = [UIColor redColor];

    NSMutableArray *arrDown = [[NSMutableArray alloc] init];
    [arrDown addObjectsFromArray:arg2];
    [arrDown addObject:button];

    %orig(arg1, arrDown);
}

%end

%ctor {
    %init;
    
    // Auto-connect on start if RPC is enabled
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:@"DiscordRPCEnabled"];
    if (enabled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[DiscordRPCManager sharedManager] connect];
        });
    }
}
