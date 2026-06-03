#import "SettingsViewController.h"
#import "DiscordRPCManager.h"

// Redefine NSLog to log to both system console and file
#define NSLog(format, ...) RPCLog(format, ##__VA_ARGS__)

#define kDiscordRPCEnabledKey @"DiscordRPCEnabled"
#define kDiscordRPCTokenKey @"DiscordRPCToken"
#define kDiscordRPCClientIDKey @"DiscordRPCClientID"
#define kDefaultClientID @"1134789502930694144"

// --- Custom Log Viewer View Controller ---
@interface LogViewerViewController : UIViewController
@end

@implementation LogViewerViewController {
    UITextView *_textView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Discord RPC Logs";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // Set navigation bar items
    UIBarButtonItem *refreshBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                                target:self
                                                                                action:@selector(loadLogs)];
    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(clearLogs)];
    self.navigationItem.rightBarButtonItems = @[refreshBtn, clearBtn];
    
    // Create text view
    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.editable = NO;
    _textView.font = [UIFont fontWithName:@"CourierNewPSMT" size:12.0] ?: [UIFont systemFontOfSize:12.0 weight:UIFontWeightLight];
    _textView.backgroundColor = [UIColor systemBackgroundColor];
    _textView.textColor = [UIColor labelColor];
    _textView.alwaysBounceVertical = YES;
    [self.view addSubview:_textView];
    
    [self loadLogs];
}

- (void)loadLogs {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (paths.count > 0) {
        NSString *documentsDirectory = [paths firstObject];
        NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"discord_rpc.log"];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:logPath]) {
            NSError *error = nil;
            NSString *logContent = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:&error];
            if (!error && logContent) {
                _textView.text = logContent;
                // Auto scroll to bottom
                if (logContent.length > 0) {
                    NSRange range = NSMakeRange(logContent.length - 1, 1);
                    [_textView scrollRangeToVisible:range];
                }
                return;
            }
        }
    }
    _textView.text = @"No logs found yet.";
}

- (void)clearLogs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear Logs"
                                                                   message:@"Are you sure you want to clear the logs file?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count > 0) {
            NSString *documentsDirectory = [paths firstObject];
            NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"discord_rpc.log"];
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if ([fileManager fileExistsAtPath:logPath]) {
                [fileManager removeItemAtPath:logPath error:nil];
            }
        }
        [self loadLogs];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

// --- Custom Sub-Settings VC for Selecting Activity ---
@interface ActivityStatusViewController : UITableViewController
@end

@implementation ActivityStatusViewController {
    NSArray *_options;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Choose Activity Status";
    _options = @[
        @"🎵 Normal (Chỉ nghe nhạc)",
        @"🚗 Commuting (Đang đi đường)",
        @"🏃 Jogging (Đang chạy bộ)",
        @"💤 Chilling (Đang thư giãn)",
        @"📚 Studying (Đang học bài)",
        @"🎮 Gaming (Đang chơi game)",
        @"🏋️ Working Out (Đang tập thể dục)"
    ];
    self.tableView.tableFooterView = [[UIView alloc] init];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"OptionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
    }
    
    cell.textLabel.text = _options[indexPath.row];
    
    NSInteger currentStatus = [[NSUserDefaults standardUserDefaults] integerForKey:@"DiscordRPCActivityStatus"];
    if (indexPath.row == currentStatus) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    [[NSUserDefaults standardUserDefaults] setInteger:indexPath.row forKey:@"DiscordRPCActivityStatus"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self.tableView reloadData];
    
    // Update presence immediately without full reconnection if connected
    if ([DiscordRPCManager sharedManager].isConnected) {
        [[DiscordRPCManager sharedManager] sendPresenceUpdate];
    } else {
        [[DiscordRPCManager sharedManager] connect];
    }
    
    // Pop back to main settings
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface SettingsViewController ()

@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *quickSelectSwitch;
@property (nonatomic, strong) UISwitch *artworkSwitch;
@property (nonatomic, strong) UISwitch *timeSwitch;
@property (nonatomic, strong) UISwitch *albumSwitch;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UITextField *clientIDField;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Discord RPC Settings";
    
    // Set standard navigation bar items
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                 target:self
                                                                                 action:@selector(closeButtonTapped)];
    self.navigationItem.leftBarButtonItem = closeButton;
    
    UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                target:self
                                                                                action:@selector(saveButtonTapped)];
    self.navigationItem.rightBarButtonItem = saveButton;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    
    // Register delegate and dataSource if needed (done automatically by UITableViewController)
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

    // Initialize settings defaults if first run
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kDiscordRPCEnabledKey] == nil) {
        [defaults setBool:NO forKey:kDiscordRPCEnabledKey];
    }
    if ([defaults objectForKey:@"DiscordRPCQuickSelectOnStartup"] == nil) {
        [defaults setBool:YES forKey:@"DiscordRPCQuickSelectOnStartup"];
    }
    if ([defaults objectForKey:@"DiscordRPCShowArtwork"] == nil) {
        [defaults setBool:YES forKey:@"DiscordRPCShowArtwork"];
    }
    if ([defaults objectForKey:@"DiscordRPCShowTime"] == nil) {
        [defaults setBool:YES forKey:@"DiscordRPCShowTime"];
    }
    if ([defaults objectForKey:@"DiscordRPCShowAlbum"] == nil) {
        [defaults setBool:YES forKey:@"DiscordRPCShowAlbum"];
    }
    [defaults synchronize];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusDidChange)
                                                 name:DiscordRPCStatusDidChangeNotification
                                               object:nil];
}

- (void)statusDidChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)closeButtonTapped {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveButtonTapped {
    [self.view endEditing:YES];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.enabledSwitch.on forKey:kDiscordRPCEnabledKey];
    [defaults setBool:self.quickSelectSwitch.on forKey:@"DiscordRPCQuickSelectOnStartup"];
    [defaults setBool:self.artworkSwitch.on forKey:@"DiscordRPCShowArtwork"];
    [defaults setBool:self.timeSwitch.on forKey:@"DiscordRPCShowTime"];
    [defaults setBool:self.albumSwitch.on forKey:@"DiscordRPCShowAlbum"];
    [defaults setObject:self.tokenField.text forKey:kDiscordRPCTokenKey];
    [defaults setObject:self.clientIDField.text forKey:kDiscordRPCClientIDKey];
    [defaults synchronize];
    
    NSLog(@"[DiscordRPC] Settings saved. Enabled: %d", self.enabledSwitch.on);
    
    // Reconnect/disconnect RPC connection based on new settings
    if (self.enabledSwitch.on) {
        [[DiscordRPCManager sharedManager] reconnect];
    } else {
        [[DiscordRPCManager sharedManager] disconnect];
    }
    
    // Present a toast or alert, then close
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Settings Saved"
                                                                   message:@"Your settings have been saved successfully."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 7; // General settings: Status, Enable, Activity, Quick Select, Artwork, Time, Album
    if (section == 1) return 2; // Discord Credentials
    if (section == 2) return 3; // Help & Links & Logs
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"General Configuration";
    if (section == 1) return @"Discord Credentials";
    if (section == 2) return @"Help & Links";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        return @"Caution: Never share your Discord token with anyone. It gives full access to your account.";
    }
    if (section == 2) {
        return @"YTMusicDiscordRPC Tweak v1.0.0.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"SettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
    }
    
    // Reset cell properties
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    for (UIView *view in cell.contentView.subviews) {
        if ([view isKindOfClass:[UITextField class]]) {
            [view removeFromSuperview];
        }
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Connection Status";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            DiscordRPCManager *manager = [DiscordRPCManager sharedManager];
            if (manager.isConnected) {
                cell.detailTextLabel.text = @"Connected";
                cell.detailTextLabel.textColor = [UIColor systemGreenColor];
            } else if (manager.isConnecting) {
                cell.detailTextLabel.text = @"Connecting...";
                cell.detailTextLabel.textColor = [UIColor systemOrangeColor];
            } else {
                cell.detailTextLabel.text = @"Disconnected";
                cell.detailTextLabel.textColor = [UIColor systemRedColor];
            }
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Enable Discord RPC";
            if (!self.enabledSwitch) {
                self.enabledSwitch = [[UISwitch alloc] init];
                self.enabledSwitch.on = [defaults boolForKey:kDiscordRPCEnabledKey];
            }
            cell.accessoryView = self.enabledSwitch;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Current Activity";
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            
            NSInteger currentStatus = [defaults integerForKey:@"DiscordRPCActivityStatus"];
            NSArray *options = @[
                @"🎵 Normal (Chỉ nghe nhạc)",
                @"🚗 Commuting (Đang đi đường)",
                @"🏃 Jogging (Đang chạy bộ)",
                @"💤 Chilling (Đang thư giãn)",
                @"📚 Studying (Đang học bài)",
                @"🎮 Gaming (Đang chơi game)",
                @"🏋️ Working Out (Đang tập thể dục)"
            ];
            if (currentStatus >= 0 && currentStatus < options.count) {
                cell.detailTextLabel.text = options[currentStatus];
            } else {
                cell.detailTextLabel.text = options[0];
            }
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Quick Select on Startup";
            if (!self.quickSelectSwitch) {
                self.quickSelectSwitch = [[UISwitch alloc] init];
                self.quickSelectSwitch.on = [defaults boolForKey:@"DiscordRPCQuickSelectOnStartup"];
            }
            cell.accessoryView = self.quickSelectSwitch;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Show Album Artwork";
            if (!self.artworkSwitch) {
                self.artworkSwitch = [[UISwitch alloc] init];
                self.artworkSwitch.on = [defaults boolForKey:@"DiscordRPCShowArtwork"];
            }
            cell.accessoryView = self.artworkSwitch;
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"Show Elapsed Time";
            if (!self.timeSwitch) {
                self.timeSwitch = [[UISwitch alloc] init];
                self.timeSwitch.on = [defaults boolForKey:@"DiscordRPCShowTime"];
            }
            cell.accessoryView = self.timeSwitch;
        } else if (indexPath.row == 6) {
            cell.textLabel.text = @"Show Album Name";
            if (!self.albumSwitch) {
                self.albumSwitch = [[UISwitch alloc] init];
                self.albumSwitch.on = [defaults boolForKey:@"DiscordRPCShowAlbum"];
            }
            cell.accessoryView = self.albumSwitch;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Token";
            
            if (!self.tokenField) {
                self.tokenField = [[UITextField alloc] init];
                self.tokenField.placeholder = @"Enter User Token";
                self.tokenField.text = [defaults stringForKey:kDiscordRPCTokenKey];
                self.tokenField.secureTextEntry = YES;
                self.tokenField.delegate = self;
                self.tokenField.clearButtonMode = UITextFieldViewModeWhileEditing;
                self.tokenField.textAlignment = NSTextAlignmentRight;
            }
            
            CGFloat textFieldX = 100.0;
            self.tokenField.frame = CGRectMake(textFieldX, 10, cell.contentView.bounds.size.width - textFieldX - 15, 24);
            self.tokenField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:self.tokenField];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"App ID";
            
            if (!self.clientIDField) {
                self.clientIDField = [[UITextField alloc] init];
                NSString *savedID = [defaults stringForKey:kDiscordRPCClientIDKey];
                self.clientIDField.text = (savedID && savedID.length > 0) ? savedID : kDefaultClientID;
                self.clientIDField.placeholder = kDefaultClientID;
                self.clientIDField.delegate = self;
                self.clientIDField.keyboardType = UIKeyboardTypeNumberPad;
                self.clientIDField.clearButtonMode = UITextFieldViewModeWhileEditing;
                self.clientIDField.textAlignment = NSTextAlignmentRight;
            }
            
            CGFloat textFieldX = 100.0;
            self.clientIDField.frame = CGRectMake(textFieldX, 10, cell.contentView.bounds.size.width - textFieldX - 15, 24);
            self.clientIDField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:self.clientIDField];
        }
    } else if (indexPath.section == 2) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
        if (indexPath.row == 0) {
            cell.textLabel.text = @"How to get Token";
            cell.detailTextLabel.text = @"Guide";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Discord Developer Portal";
            cell.detailTextLabel.text = @"Open Link";
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"View Logs";
            cell.detailTextLabel.text = @"Show Log File";
        }
    }
    
    return cell;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 0) {
        if (indexPath.row == 2) {
            // Push ActivityStatusViewController
            ActivityStatusViewController *activityVC = [[ActivityStatusViewController alloc] init];
            [self.navigationController pushViewController:activityVC animated:YES];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            // Guide URL
            NSURL *url = [NSURL URLWithString:@"https://pcstrike.com/how-to-get-discord-token/"];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        } else if (indexPath.row == 1) {
            // Dev portal URL
            NSURL *url = [NSURL URLWithString:@"https://discord.com/developers/applications"];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        } else if (indexPath.row == 2) {
            // Push LogViewerViewController
            LogViewerViewController *logVC = [[LogViewerViewController alloc] init];
            [self.navigationController pushViewController:logVC animated:YES];
        }
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
