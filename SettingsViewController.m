#import "SettingsViewController.h"
#import "DiscordRPCManager.h"

#define kDiscordRPCEnabledKey @"DiscordRPCEnabled"
#define kDiscordRPCTokenKey @"DiscordRPCToken"
#define kDiscordRPCClientIDKey @"DiscordRPCClientID"
#define kDefaultClientID @"1134789502930694144"

@interface SettingsViewController ()

@property (nonatomic, strong) UISwitch *enabledSwitch;
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
}

- (void)closeButtonTapped {
    [self.view endEditing:YES];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveButtonTapped {
    [self.view endEditing:YES];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.enabledSwitch.on forKey:kDiscordRPCEnabledKey];
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
    if (section == 0) return 1; // General settings
    if (section == 1) return 2; // Discord Credentials
    if (section == 2) return 2; // Instructions & Links
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
            cell.textLabel.text = @"Enable Discord RPC";
            if (!self.enabledSwitch) {
                self.enabledSwitch = [[UISwitch alloc] init];
                self.enabledSwitch.on = [defaults boolForKey:kDiscordRPCEnabledKey];
            }
            cell.accessoryView = self.enabledSwitch;
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
        }
    }
    
    return cell;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            // Guide URL
            NSURL *url = [NSURL URLWithString:@"https://pcstrike.com/how-to-get-discord-token/"];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        } else if (indexPath.row == 1) {
            // Dev portal URL
            NSURL *url = [NSURL URLWithString:@"https://discord.com/developers/applications"];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
