#import <Foundation/Foundation.h>

// Global logging functions to log to Documents/discord_rpc.log
void writeRPCLog(NSString *format, ...);
#define RPCLog(format, ...) writeRPCLog(format, ##__VA_ARGS__)

extern NSString *const DiscordRPCStatusDidChangeNotification;

@interface DiscordRPCManager : NSObject

@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isConnecting;

+ (instancetype)sharedManager;

- (void)connect;
- (void)disconnect;
- (void)reconnect;
- (void)sendPresenceUpdate;

- (void)updatePresenceWithTitle:(NSString *)title 
                         artist:(NSString *)artist 
                          album:(NSString *)album 
                       duration:(double)duration 
                    elapsedTime:(double)elapsedTime 
                      isPlaying:(BOOL)isPlaying 
                        videoID:(NSString *)videoID;

@end
