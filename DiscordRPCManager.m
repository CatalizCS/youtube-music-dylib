#import "DiscordRPCManager.h"

// Define the global C function first (which calls the system NSLog)
void writeRPCLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // 1. Log to the native iOS system Console (using the original NSLog function)
    NSLog(@"[DiscordRPC] %@", message);
    
    // 2. Log to Documents/discord_rpc.log
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *documentsDirectory = [paths firstObject];
        NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"discord_rpc.log"];
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
        
        NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", dateString, message];
        NSData *logData = [logLine dataUsingEncoding:NSUTF8StringEncoding];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:logPath]) {
            [fileManager createFileAtPath:logPath contents:nil attributes:nil];
        }
        
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:logData];
            [fileHandle closeFile];
        }
    }
}

// Redefine NSLog for all subsequent code in this file to write to our log file
#define NSLog(format, ...) RPCLog(format, ##__VA_ARGS__)

#define kDiscordRPCEnabledKey @"DiscordRPCEnabled"
#define kDiscordRPCTokenKey @"DiscordRPCToken"
#define kDiscordRPCClientIDKey @"DiscordRPCClientID"
#define kDefaultClientID @"1134789502930694144"

@interface DiscordRPCManager () <NSURLSessionWebSocketDelegate>

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionWebSocketTask *webSocketTask;
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, strong) NSNumber *lastSequenceNumber;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isConnecting;

// Cache last track info
@property (nonatomic, strong) NSString *lastTitle;
@property (nonatomic, strong) NSString *lastArtist;
@property (nonatomic, strong) NSString *lastAlbum;
@property (nonatomic, assign) double lastDuration;
@property (nonatomic, assign) double lastElapsedTime;
@property (nonatomic, assign) BOOL lastIsPlaying;
@property (nonatomic, strong) NSString *lastVideoID;
@property (nonatomic, assign) double lastPlaybackUpdateTime;

@end

@implementation DiscordRPCManager

+ (instancetype)sharedManager {
    static DiscordRPCManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isConnected = NO;
        _isConnecting = NO;
    }
    return self;
}

- (void)connect {
    if (self.isConnected || self.isConnecting) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:kDiscordRPCEnabledKey];
    NSString *token = [defaults stringForKey:kDiscordRPCTokenKey];

    if (!enabled || !token || token.length == 0) {
        NSLog(@"[DiscordRPC] Cannot connect: Tweak disabled or token is missing.");
        return;
    }

    NSLog(@"[DiscordRPC] Connecting to Discord Gateway...");
    self.isConnecting = YES;

    // Reset sequence number
    self.lastSequenceNumber = nil;

    NSURL *gatewayURL = [NSURL URLWithString:@"wss://gateway.discord.gg/?v=9&encoding=json"];
    self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:self
                                            delegateQueue:[NSOperationQueue mainQueue]];
    self.webSocketTask = [self.session webSocketTaskWithURL:gatewayURL];
    self.webSocketTask.maximumMessageSize = 10485760; // 10MB for large READY payloads
    [self.webSocketTask resume];

    [self receiveMessage];
}

- (void)disconnect {
    NSLog(@"[DiscordRPC] Disconnecting...");
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(connect) object:nil];
    
    if (self.heartbeatTimer) {
        [self.heartbeatTimer invalidate];
        self.heartbeatTimer = nil;
    }

    if (self.webSocketTask) {
        [self.webSocketTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        self.webSocketTask = nil;
    }

    self.session = nil;
    self.isConnected = NO;
    self.isConnecting = NO;
}

- (void)reconnect {
    [self disconnect];
    [self connect];
}

- (void)handleDisconnect {
    NSLog(@"[DiscordRPC] Connection disconnected or failed.");
    [self disconnect];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:kDiscordRPCEnabledKey];
    if (enabled) {
        NSLog(@"[DiscordRPC] Retrying connection in 5 seconds...");
        [self performSelector:@selector(connect) withObject:nil afterDelay:5.0];
    }
}

- (void)sendJSONPayload:(NSDictionary *)payload {
    if (!self.webSocketTask) return;

    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (error || !jsonData) {
        NSLog(@"[DiscordRPC] Failed to serialize JSON payload: %@", error);
        return;
    }

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSURLSessionWebSocketMessage *message = [[NSURLSessionWebSocketMessage alloc] initWithString:jsonString];
    
    [self.webSocketTask sendMessage:message completionHandler:^(NSError * _Nullable sendError) {
        if (sendError) {
            NSLog(@"[DiscordRPC] Failed to send WebSocket message: %@", sendError);
        }
    }];
}

- (void)receiveMessage {
    if (!self.webSocketTask) return;

    __weak typeof(self) weakSelf = self;
    [self.webSocketTask receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            NSLog(@"[DiscordRPC] WebSocket receive error: %@", error);
            [strongSelf handleDisconnect];
            return;
        }

        if (message.type == NSURLSessionWebSocketMessageTypeString) {
            NSData *jsonData = [message.string dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if (payload) {
                [strongSelf handlePayload:payload];
            }
        }

        // Keep receiving messages recursively
        [strongSelf receiveMessage];
    }];
}

- (void)handlePayload:(NSDictionary *)payload {
    NSNumber *op = payload[@"op"];
    id s = payload[@"s"];
    if (s && s != [NSNull null]) {
        self.lastSequenceNumber = s;
    }

    int opCode = [op intValue];
    if (opCode == 10) { // Hello
        NSLog(@"[DiscordRPC] Received Hello from gateway.");
        NSDictionary *d = payload[@"d"];
        double heartbeatInterval = [d[@"heartbeat_interval"] doubleValue] / 1000.0;
        [self startHeartbeatWithInterval:heartbeatInterval];
        [self sendIdentify];
    } else if (opCode == 11) { // Heartbeat ACK
        // Heartbeat acknowledged by server
    } else if (opCode == 1) { // Heartbeat request from server
        [self sendHeartbeat];
    } else if (opCode == 0) { // Event Dispatch
        NSString *t = payload[@"t"];
        if ([t isEqualToString:@"READY"]) {
            NSLog(@"[DiscordRPC] Connected to Discord successfully!");
            self.isConnected = YES;
            self.isConnecting = NO;
            // Send pending presence if exists
            if (self.lastTitle) {
                [self sendPresenceUpdate];
            }
        }
    }
}

- (void)startHeartbeatWithInterval:(double)interval {
    if (self.heartbeatTimer) {
        [self.heartbeatTimer invalidate];
    }
    
    // Heartbeat timer on main run loop
    self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                           target:self
                                                         selector:@selector(sendHeartbeat)
                                                         userInfo:nil
                                                          repeats:YES];
    
    // Send immediate heartbeat first
    [self sendHeartbeat];
}

- (void)sendHeartbeat {
    NSLog(@"[DiscordRPC] Sending Heartbeat...");
    NSDictionary *payload = @{
        @"op": @1,
        @"d": self.lastSequenceNumber ?: [NSNull null]
    };
    [self sendJSONPayload:payload];
}

- (void)sendIdentify {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *token = [defaults stringForKey:kDiscordRPCTokenKey];

    NSLog(@"[DiscordRPC] Identifying to Gateway...");
    NSDictionary *payload = @{
        @"op": @2,
        @"d": @{
            @"token": token ?: @"",
            @"capabilities": @125,
            @"properties": @{
                @"$os": @"ios",
                @"$browser": @"Discord iOS",
                @"$device": @"iPhone"
            },
            @"presence": @{
                @"status": @"online",
                @"since": @0,
                @"activities": @[],
                @"afk": @NO
            },
            @"compress": @NO
        }
    };
    [self sendJSONPayload:payload];
}

- (void)updatePresenceWithTitle:(NSString *)title 
                         artist:(NSString *)artist 
                          album:(NSString *)album 
                       duration:(double)duration 
                    elapsedTime:(double)elapsedTime 
                      isPlaying:(BOOL)isPlaying 
                        videoID:(NSString *)videoID {
    
    // Check if anything actually changed (with a minor leeway for elapsed time)
    BOOL changed = ![title isEqualToString:self.lastTitle] ||
                   ![artist isEqualToString:self.lastArtist] ||
                   ![album isEqualToString:self.lastAlbum] ||
                   (isPlaying != self.lastIsPlaying) ||
                   ![videoID isEqualToString:self.lastVideoID] ||
                   (fabs(elapsedTime - self.lastElapsedTime) > 3.0 && isPlaying);

    if (!changed) {
        return;
    }

    self.lastTitle = title;
    self.lastArtist = artist;
    self.lastAlbum = album;
    self.lastDuration = duration;
    self.lastElapsedTime = elapsedTime;
    self.lastIsPlaying = isPlaying;
    self.lastVideoID = videoID;
    self.lastPlaybackUpdateTime = [[NSDate date] timeIntervalSince1970];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL enabled = [defaults boolForKey:kDiscordRPCEnabledKey];
    if (!enabled) {
        if (self.isConnected) {
            [self disconnect];
        }
        return;
    }

    if (!self.isConnected) {
        [self connect];
        return;
    }

    [self sendPresenceUpdate];
}

- (void)sendPresenceUpdate {
    if (!self.isConnected) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *clientID = [defaults stringForKey:kDiscordRPCClientIDKey];
    if (!clientID || clientID.length == 0) {
        clientID = kDefaultClientID;
    }

    NSMutableArray *activities = [[NSMutableArray alloc] init];
    
    if (self.lastTitle && self.lastTitle.length > 0) {
        NSMutableDictionary *activity = [[NSMutableDictionary alloc] init];
        [activity setObject:@"YouTube Music" forKey:@"name"];
        [activity setObject:@2 forKey:@"type"]; // 2 = Listening
        [activity setObject:clientID forKey:@"application_id"];
        [activity setObject:self.lastTitle forKey:@"details"];
        
        NSString *artistState = self.lastArtist ?: @"Unknown Artist";
        if (!self.lastIsPlaying) {
            artistState = [NSString stringWithFormat:@"%@ (Paused)", artistState];
        }
        [activity setObject:artistState forKey:@"state"];

        NSMutableDictionary *assets = [[NSMutableDictionary alloc] init];
        if (self.lastVideoID && self.lastVideoID.length > 0) {
            NSString *thumbURL = [NSString stringWithFormat:@"https://img.youtube.com/vi/%@/hqdefault.jpg", self.lastVideoID];
            [assets setObject:thumbURL forKey:@"large_image"];
        } else {
            // Default image asset if we don't have video ID
            [assets setObject:@"ytmusic_logo" forKey:@"large_image"];
        }
        
        if (self.lastAlbum && self.lastAlbum.length > 0) {
            [assets setObject:self.lastAlbum forKey:@"large_text"];
        } else {
            [assets setObject:self.lastIsPlaying ? @"Listening" : @"Paused" forKey:@"large_text"];
        }
        [activity setObject:assets forKey:@"assets"];

        if (self.lastIsPlaying && self.lastDuration > 0) {
            NSMutableDictionary *timestamps = [[NSMutableDictionary alloc] init];
            // Timestamps must be in UTC milliseconds epoch
            double currentEpochMs = [[NSDate date] timeIntervalSince1970] * 1000.0;
            double startEpochMs = currentEpochMs - (self.lastElapsedTime * 1000.0);
            double endEpochMs = startEpochMs + (self.lastDuration * 1000.0);
            
            [timestamps setObject:@((long long)startEpochMs) forKey:@"start"];
            [timestamps setObject:@((long long)endEpochMs) forKey:@"end"];
            [activity setObject:timestamps forKey:@"timestamps"];
        }

        [activities addObject:activity];
    }

    NSDictionary *payload = @{
        @"op": @3,
        @"d": @{
            @"since": @0,
            @"activities": activities,
            @"status": @"online",
            @"afk": @NO
        }
    };

    NSLog(@"[DiscordRPC] Updating presence: %@ - %@", self.lastTitle, self.lastArtist);
    [self sendJSONPayload:payload];
}

#pragma mark - NSURLSessionWebSocketDelegate

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didOpenWithProtocol:(NSString *)protocol {
    NSLog(@"[DiscordRPC] WebSocket connection opened.");
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData *)reason {
    NSLog(@"[DiscordRPC] WebSocket closed with code: %ld", (long)closeCode);
    [self handleDisconnect];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"[DiscordRPC] WebSocket session task failed with error: %@", error);
        [self handleDisconnect];
    }
}

@end
