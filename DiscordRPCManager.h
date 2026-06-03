#import <Foundation/Foundation.h>

@interface DiscordRPCManager : NSObject

@property (nonatomic, readonly) BOOL isConnected;

+ (instancetype)sharedManager;

- (void)connect;
- (void)disconnect;
- (void)reconnect;

- (void)updatePresenceWithTitle:(NSString *)title 
                         artist:(NSString *)artist 
                          album:(NSString *)album 
                       duration:(double)duration 
                    elapsedTime:(double)elapsedTime 
                      isPlaying:(BOOL)isPlaying 
                        videoID:(NSString *)videoID;

@end
