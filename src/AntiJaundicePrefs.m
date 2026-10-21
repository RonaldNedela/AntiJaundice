#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)property forKey:(NSString *)key;
- (NSString *)identifier;
@end

@interface PSTableCell : UITableViewCell
- (PSSpecifier *)specifier;
- (id)target;
- (id)control;
- (id)value;
- (void)setValue:(id)value;
@end

@interface PSListController : UIViewController
- (id)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)specifiers;
- (PSSpecifier *)specifierForID:(NSString *)identifier;
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
- (void)reloadSpecifier:(PSSpecifier *)specifier;
- (void)reloadSpecifiers;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (UITableView *)table;
@end

@interface AntiJaundiceRootListController : PSListController <UITextFieldDelegate>
@end

#pragma mark - Helper Functions

static UISlider *findSliderInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UISlider class]]) return (UISlider *)view;
    if ([view respondsToSelector:@selector(control)]) {
        id c = [view performSelector:@selector(control)];
        if ([c isKindOfClass:[UISlider class]]) return (UISlider *)c;
    }
    for (UIView *sub in view.subviews) {
        UISlider *s = findSliderInView(sub);
        if (s) return s;
    }
    return nil;
}

static UITextField *findTextFieldInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITextField class]]) return (UITextField *)view;
    if ([view respondsToSelector:@selector(textField)]) {
        id tf = [view performSelector:@selector(textField)];
        if ([tf isKindOfClass:[UITextField class]]) return (UITextField *)tf;
    }
    for (UIView *sub in view.subviews) {
        UITextField *tf = findTextFieldInView(sub);
        if (tf) return tf;
    }
    return nil;
}

#pragma mark - AntiJaundiceRootListController Implementation

@implementation AntiJaundiceRootListController

- (NSArray *)specifiers {
    NSArray *specs = [super specifiers];
    if (!specs || [specs count] == 0) {
        specs = [self loadSpecifiersFromPlistName:@"Root" target:self];
        if (!specs || [specs count] == 0) {
            specs = [self loadSpecifiersFromPlistName:@"AntiJaundice" target:self];
        }
        [self setSpecifiers:specs];
    }
    return specs;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AntiJaundice";
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(aj_textFieldDidEnd:)
                                                 name:UITextFieldTextDidEndEditingNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    UITextField *tf = findTextFieldInView(cell);
    if (tf) {
        tf.delegate = self;
        tf.returnKeyType = UIReturnKeyDone;
        tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        [tf removeTarget:self action:@selector(aj_returnPressed:) forControlEvents:UIControlEventEditingDidEndOnExit];
        [tf addTarget:self action:@selector(aj_returnPressed:) forControlEvents:UIControlEventEditingDidEndOnExit];
        
        // Ensure displayed text matches stored preference
        if ([cell respondsToSelector:@selector(specifier)]) {
            PSSpecifier *spec = [cell performSelector:@selector(specifier)];
            NSString *key = [spec propertyForKey:@"key"];
            if (key && ![tf isFirstResponder]) {
                CFPropertyListRef propVal = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.ronci.antijaundice"));
                if (propVal) {
                    CGFloat fVal = [(__bridge id)propVal floatValue];
                    if ([key isEqualToString:@"intensity"]) {
                        tf.text = [NSString stringWithFormat:@"%.1f", fVal];
                    } else {
                        tf.text = [NSString stringWithFormat:@"%.0f", fVal];
                    }
                    CFRelease(propVal);
                }
            }
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self commitValueFromTextField:textField];
    return YES;
}

- (void)aj_returnPressed:(UITextField *)textField {
    [textField resignFirstResponder];
    [self commitValueFromTextField:textField];
}

- (void)aj_textFieldDidEnd:(NSNotification *)note {
    if ([note.object isKindOfClass:[UITextField class]]) {
        [self commitValueFromTextField:(UITextField *)note.object];
    }
}

- (void)commitValueFromTextField:(UITextField *)tf {
    if (!tf) return;
    
    UIView *view = tf;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) {
        view = view.superview;
    }
    UITableViewCell *cell = (UITableViewCell *)view;
    if (!cell || ![cell respondsToSelector:@selector(specifier)]) return;
    
    PSSpecifier *spec = [cell performSelector:@selector(specifier)];
    if (!spec) return;
    
    NSString *key = [spec propertyForKey:@"key"];
    if (!key) return;
    
    CGFloat minVal = 0.0, maxVal = 100.0;
    BOOL isFloat = NO;
    if ([key isEqualToString:@"edgeOffset"]) {
        minVal = 0.0; maxVal = 40.0; isFloat = NO;
    } else if ([key isEqualToString:@"bandWidth"]) {
        minVal = 50.0; maxVal = 250.0; isFloat = NO;
    } else if ([key isEqualToString:@"intensity"]) {
        minVal = 0.1; maxVal = 20.0; isFloat = YES;
    } else if ([key isEqualToString:@"colorHue"]) {
        minVal = 0.0; maxVal = 100.0; isFloat = NO;
    } else {
        return;
    }
    
    NSString *text = tf.text ?: @"";
    text = [text stringByReplacingOccurrencesOfString:@"," withString:@"."];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    CGFloat val = [text floatValue];
    if (val < minVal) val = minVal;
    if (val > maxVal) val = maxVal;
    
    if (isFloat) {
        tf.text = [NSString stringWithFormat:@"%.1f", val];
    } else {
        tf.text = [NSString stringWithFormat:@"%.0f", val];
    }
    
    NSNumber *numVal = @(val);
    
    // 1. Save to CFPreferences
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)numVal, CFSTR("com.ronci.antijaundice"));
    CFPreferencesAppSynchronize(CFSTR("com.ronci.antijaundice"));
    
    // 2. Direct disk backup for rootless
    NSArray *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.ronci.antijaundice.plist",
        @"/var/mobile/Library/Preferences/com.ronci.antijaundice.plist"
    ];
    for (NSString *p in paths) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithContentsOfFile:p] ?: [NSMutableDictionary dictionary];
        dict[key] = numVal;
        [dict writeToFile:p atomically:YES];
    }
    
    // 3. Post Darwin notification immediately to update SpringBoard filter live!
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.ronci.antijaundice/prefsChanged"),
        NULL,
        NULL,
        YES
    );
    
    // 4. Update the companion slider model & animate the slider!
    NSString *sliderId = [NSString stringWithFormat:@"%@_slider", key];
    PSSpecifier *sliderSpec = [self specifierForID:sliderId];
    if (sliderSpec) {
        [self setPreferenceValue:numVal specifier:sliderSpec];
        [self reloadSpecifier:sliderSpec animated:YES];
    }
    
    // Update visible slider cell directly
    UITableView *tv = [self table];
    if (tv) {
        for (UITableViewCell *c in tv.visibleCells) {
            if (c == cell) continue;
            if ([c respondsToSelector:@selector(specifier)]) {
                PSSpecifier *s = [c performSelector:@selector(specifier)];
                if ([[s propertyForKey:@"key"] isEqualToString:key]) {
                    UISlider *slider = findSliderInView(c);
                    if (slider) {
                        [slider setValue:val animated:YES];
                        [slider sendActionsForControlEvents:UIControlEventValueChanged];
                    }
                }
            }
        }
    }
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    
    if (!specifier) return;
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *specId = [specifier identifier];
    
    if (!key || [key isEqualToString:@"enabled"]) return;
    
    // If the slider was moved by the user:
    if ([specId hasSuffix:@"_slider"] && [value respondsToSelector:@selector(floatValue)]) {
        CGFloat fVal = [value floatValue];
        
        // 1. Direct update to disk & CFPreferences
        NSNumber *numVal = @(fVal);
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)numVal, CFSTR("com.ronci.antijaundice"));
        CFPreferencesAppSynchronize(CFSTR("com.ronci.antijaundice"));
        
        // 2. Post Darwin notification immediately
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.ronci.antijaundice/prefsChanged"), NULL, NULL, YES);
        
        // 3. Update the companion text field in real time!
        UITableView *tv = [self table];
        if (tv) {
            for (UITableViewCell *c in tv.visibleCells) {
                if ([c respondsToSelector:@selector(specifier)]) {
                    PSSpecifier *s = [c performSelector:@selector(specifier)];
                    if ([[s propertyForKey:@"key"] isEqualToString:key] && [[s identifier] hasSuffix:@"_text"]) {
                        UITextField *tf = findTextFieldInView(c);
                        if (tf && ![tf isFirstResponder]) {
                            if ([key isEqualToString:@"intensity"]) {
                                tf.text = [NSString stringWithFormat:@"%.1f", fVal];
                            } else {
                                tf.text = [NSString stringWithFormat:@"%.0f", fVal];
                            }
                        }
                    }
                }
            }
        }
    }
}

@end
