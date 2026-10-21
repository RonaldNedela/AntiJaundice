#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@class AntiJaundiceWindow;
@class AntiJaundiceViewController;
@class AntiJaundiceView;

static AntiJaundiceWindow *gOverlayWindow = nil;
static AntiJaundiceViewController *gOverlayVC = nil;

static CGRect getEffectiveScreenBounds(void);
static void updateWindowFrames(void);
static void setupOverlayIfReady(void);
static void reloadPreferences(void);

@interface AntiJaundiceContainerView : UIView
@end

@implementation AntiJaundiceContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return NO;
}

@end

@interface AntiJaundiceView : UIView {
@public
    CAGradientLayer *_topLayer;
    CAShapeLayer *_topMask;
    CAGradientLayer *_bottomLayer;
    CAShapeLayer *_bottomMask;
    CAGradientLayer *_leftLayer;
    CAShapeLayer *_leftMask;
    CAGradientLayer *_rightLayer;
    CAShapeLayer *_rightMask;
    
    CGSize _lastGeometrySize;
    CGFloat _lastHue;
    CGFloat _lastAlpha;
    CGFloat _lastEdgeOffset;
    CGFloat _lastBandWidth;
    BOOL _lastFilterEnabled;
}
@property (nonatomic, assign) BOOL isFilterEnabled;
@property (nonatomic, assign) CGFloat intensity;
@property (nonatomic, assign) CGFloat edgeOffset;
@property (nonatomic, assign) CGFloat bandWidth;
@property (nonatomic, assign) CGFloat colorHue;
@property (nonatomic, assign) NSInteger colorPreset;

- (void)updateGradientAppearance;
- (void)updateGradientGeometry;
@end

@implementation AntiJaundiceView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        
        _isFilterEnabled = YES;
        _intensity = 0.08;
        _edgeOffset = 10.0;
        _bandWidth = 100.0;
        _colorHue = 50.0;
        _colorPreset = 0;
        
        _lastGeometrySize = CGSizeZero;
        _lastHue = -1.0;
        _lastAlpha = -1.0;
        _lastEdgeOffset = -1.0;
        _lastBandWidth = -1.0;
        _lastFilterEnabled = NO;
        
        // 1. Top Layer & Mask
        _topLayer = [CAGradientLayer layer];
        _topMask = [CAShapeLayer layer];
        _topLayer.mask = _topMask;
        [self.layer addSublayer:_topLayer];
        
        // 2. Bottom Layer & Mask
        _bottomLayer = [CAGradientLayer layer];
        _bottomMask = [CAShapeLayer layer];
        _bottomLayer.mask = _bottomMask;
        [self.layer addSublayer:_bottomLayer];
        
        // 3. Left Layer & Mask
        _leftLayer = [CAGradientLayer layer];
        _leftMask = [CAShapeLayer layer];
        _leftLayer.mask = _leftMask;
        [self.layer addSublayer:_leftLayer];
        
        // 4. Right Layer & Mask
        _rightLayer = [CAGradientLayer layer];
        _rightMask = [CAShapeLayer layer];
        _rightLayer.mask = _rightMask;
        [self.layer addSublayer:_rightLayer];
        
        [self updateGradientAppearance];
        [self updateGradientGeometry];
    }
    return self;
}

- (void)setIsFilterEnabled:(BOOL)isFilterEnabled {
    if (_isFilterEnabled != isFilterEnabled) {
        _isFilterEnabled = isFilterEnabled;
        [self updateGradientAppearance];
        [self updateGradientGeometry];
    }
}

- (void)setIntensity:(CGFloat)intensity {
    if (fabs(_intensity - intensity) > 0.0001) {
        _intensity = intensity;
        [self updateGradientAppearance];
    }
}

- (void)setEdgeOffset:(CGFloat)edgeOffset {
    if (fabs(_edgeOffset - edgeOffset) > 0.1) {
        _edgeOffset = edgeOffset;
        [self updateGradientAppearance];
        [self updateGradientGeometry];
    }
}

- (void)setBandWidth:(CGFloat)bandWidth {
    if (fabs(_bandWidth - bandWidth) > 0.1) {
        _bandWidth = bandWidth;
        [self updateGradientAppearance];
        [self updateGradientGeometry];
    }
}

- (void)setColorHue:(CGFloat)colorHue {
    if (fabs(_colorHue - colorHue) > 0.1) {
        _colorHue = colorHue;
        [self updateGradientAppearance];
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return NO;
}

- (void)setFrame:(CGRect)frame {
    BOOL sizeChanged = !CGSizeEqualToSize(self.frame.size, frame.size);
    [super setFrame:frame];
    if (sizeChanged) {
        [self updateGradientGeometry];
    }
}

- (void)setBounds:(CGRect)bounds {
    BOOL sizeChanged = !CGSizeEqualToSize(self.bounds.size, bounds.size);
    [super setBounds:bounds];
    if (sizeChanged) {
        [self updateGradientGeometry];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(_lastGeometrySize, self.bounds.size)) {
        [self updateGradientGeometry];
    }
}

- (void)updateGradientAppearance {
    if (!_isFilterEnabled || _intensity <= 0.005) {
        if (_lastFilterEnabled) {
            _lastFilterEnabled = NO;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _topLayer.hidden = YES;
            _bottomLayer.hidden = YES;
            _leftLayer.hidden = YES;
            _rightLayer.hidden = YES;
            [CATransaction commit];
        }
        return;
    }
    
    // Check if parameters actually changed to avoid redundant GPU state changes
    if (_lastFilterEnabled == _isFilterEnabled &&
        fabs(_lastHue - _colorHue) < 0.01 &&
        fabs(_lastAlpha - _intensity) < 0.0001 &&
        fabs(_lastEdgeOffset - _edgeOffset) < 0.01 &&
        fabs(_lastBandWidth - _bandWidth) < 0.01) {
        return;
    }
    
    _lastFilterEnabled = _isFilterEnabled;
    _lastHue = _colorHue;
    _lastAlpha = _intensity;
    _lastEdgeOffset = _edgeOffset;
    _lastBandWidth = _bandWidth;
    
    CGFloat hueVal = _colorHue;
    if (hueVal < 0.0) hueVal = 0.0;
    if (hueVal > 100.0) hueVal = 100.0;
    CGFloat hue = 0.48 + (hueVal / 100.0) * 0.30;
    UIColor *tintColor = [UIColor colorWithHue:hue saturation:0.95 brightness:1.0 alpha:1.0];
    CGFloat r = 0.0, g = 0.52, b = 1.0;
    CGFloat dummyAlpha = 1.0;
    if (![tintColor getRed:&r green:&g blue:&b alpha:&dummyAlpha]) {
        r = 0.0; g = 0.52; b = 1.0;
    }
    
    CGFloat alpha = _intensity;
    if (alpha > 1.0) alpha = 1.0;
    if (alpha < 0.0) alpha = 0.0;
    
    CGFloat edgeOffset = _edgeOffset;
    if (edgeOffset < 0.0) edgeOffset = 0.0;
    
    CGFloat bandWidth = _bandWidth;
    if (bandWidth < 5.0) bandWidth = 5.0;
    
    CGFloat totalWidth = edgeOffset + bandWidth;
    if (totalWidth <= 0.0) return;
    CGFloat D = totalWidth;
    
    NSMutableArray *colors = [NSMutableArray array];
    NSMutableArray *locations = [NSMutableArray array];
    
    if (edgeOffset >= 1.0) {
        CGFloat locs[8] = {
            0.0 / D,
            (0.70 * edgeOffset) / D,
            edgeOffset / D,
            (edgeOffset + 0.15 * bandWidth) / D,
            (edgeOffset + 0.35 * bandWidth) / D,
            (edgeOffset + 0.65 * bandWidth) / D,
            (edgeOffset + 0.85 * bandWidth) / D,
            1.0
        };
        CGFloat alphas[8] = {
            0.0,
            0.0,
            0.05 * alpha,
            0.55 * alpha,
            1.00 * alpha,
            0.50 * alpha,
            0.15 * alpha,
            0.0
        };
        for (int i = 0; i < 8; i++) {
            UIColor *c = [UIColor colorWithRed:r green:g blue:b alpha:alphas[i]];
            [colors addObject:(id)c.CGColor];
            [locations addObject:@(locs[i])];
        }
    } else {
        CGFloat locs[7] = {
            0.0 / D,
            (0.08 * bandWidth) / D,
            (0.20 * bandWidth) / D,
            (0.35 * bandWidth) / D,
            (0.65 * bandWidth) / D,
            (0.85 * bandWidth) / D,
            1.0
        };
        CGFloat alphas[7] = {
            0.0,
            0.30 * alpha,
            0.70 * alpha,
            1.00 * alpha,
            0.50 * alpha,
            0.15 * alpha,
            0.0
        };
        for (int i = 0; i < 7; i++) {
            UIColor *c = [UIColor colorWithRed:r green:g blue:b alpha:alphas[i]];
            [colors addObject:(id)c.CGColor];
            [locations addObject:@(locs[i])];
        }
    }
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    _topLayer.colors = colors;
    _topLayer.locations = locations;
    _topLayer.hidden = NO;
    
    _bottomLayer.colors = colors;
    _bottomLayer.locations = locations;
    _bottomLayer.hidden = NO;
    
    _leftLayer.colors = colors;
    _leftLayer.locations = locations;
    _leftLayer.hidden = NO;
    
    _rightLayer.colors = colors;
    _rightLayer.locations = locations;
    _rightLayer.hidden = NO;
    
    [CATransaction commit];
}

- (void)updateGradientGeometry {
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    if (w <= 0.0 || h <= 0.0) return;
    
    if (!_isFilterEnabled || _intensity <= 0.005) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _topLayer.hidden = YES;
        _bottomLayer.hidden = YES;
        _leftLayer.hidden = YES;
        _rightLayer.hidden = YES;
        [CATransaction commit];
        return;
    }
    
    _lastGeometrySize = bounds.size;
    
    CGFloat edgeOffset = _edgeOffset;
    if (edgeOffset < 0.0) edgeOffset = 0.0;
    
    CGFloat bandWidth = _bandWidth;
    if (bandWidth < 5.0) bandWidth = 5.0;
    
    CGFloat totalWidth = edgeOffset + bandWidth;
    CGFloat maxAllowed = MIN(w / 2.0, h / 2.0);
    if (totalWidth > maxAllowed) {
        totalWidth = maxAllowed;
    }
    if (totalWidth <= 0.0) return;
    
    CGFloat bw = totalWidth;
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    // 1. Top trapezoid: (0, 0, w, bw)
    _topLayer.frame = CGRectMake(0, 0, w, bw);
    _topLayer.startPoint = CGPointMake(0.5, 0.0);
    _topLayer.endPoint = CGPointMake(0.5, 1.0);
    _topLayer.hidden = NO;
    
    UIBezierPath *topPath = [UIBezierPath bezierPath];
    [topPath moveToPoint:CGPointMake(0, 0)];
    [topPath addLineToPoint:CGPointMake(w, 0)];
    [topPath addLineToPoint:CGPointMake(w - bw, bw)];
    [topPath addLineToPoint:CGPointMake(bw, bw)];
    [topPath closePath];
    _topMask.path = topPath.CGPath;
    _topMask.frame = _topLayer.bounds;
    
    // 2. Bottom trapezoid: (0, h - bw, w, bw)
    _bottomLayer.frame = CGRectMake(0, h - bw, w, bw);
    _bottomLayer.startPoint = CGPointMake(0.5, 1.0);
    _bottomLayer.endPoint = CGPointMake(0.5, 0.0);
    _bottomLayer.hidden = NO;
    
    UIBezierPath *bottomPath = [UIBezierPath bezierPath];
    [bottomPath moveToPoint:CGPointMake(0, bw)];
    [bottomPath addLineToPoint:CGPointMake(w, bw)];
    [bottomPath addLineToPoint:CGPointMake(w - bw, 0)];
    [bottomPath addLineToPoint:CGPointMake(bw, 0)];
    [bottomPath closePath];
    _bottomMask.path = bottomPath.CGPath;
    _bottomMask.frame = _bottomLayer.bounds;
    
    // 3. Left trapezoid: (0, 0, bw, h)
    _leftLayer.frame = CGRectMake(0, 0, bw, h);
    _leftLayer.startPoint = CGPointMake(0.0, 0.5);
    _leftLayer.endPoint = CGPointMake(1.0, 0.5);
    _leftLayer.hidden = NO;
    
    UIBezierPath *leftPath = [UIBezierPath bezierPath];
    [leftPath moveToPoint:CGPointMake(0, 0)];
    [leftPath addLineToPoint:CGPointMake(bw, bw)];
    [leftPath addLineToPoint:CGPointMake(bw, h - bw)];
    [leftPath addLineToPoint:CGPointMake(0, h)];
    [leftPath closePath];
    _leftMask.path = leftPath.CGPath;
    _leftMask.frame = _leftLayer.bounds;
    
    // 4. Right trapezoid: (w - bw, 0, bw, h)
    _rightLayer.frame = CGRectMake(w - bw, 0, bw, h);
    _rightLayer.startPoint = CGPointMake(1.0, 0.5);
    _rightLayer.endPoint = CGPointMake(0.0, 0.5);
    _rightLayer.hidden = NO;
    
    UIBezierPath *rightPath = [UIBezierPath bezierPath];
    [rightPath moveToPoint:CGPointMake(bw, 0)];
    [rightPath addLineToPoint:CGPointMake(bw, h)];
    [rightPath addLineToPoint:CGPointMake(0, h - bw)];
    [rightPath addLineToPoint:CGPointMake(0, bw)];
    [rightPath closePath];
    _rightMask.path = rightPath.CGPath;
    _rightMask.frame = _rightLayer.bounds;
    
    [CATransaction commit];
}

@end

@interface AntiJaundiceViewController : UIViewController
@property (nonatomic, strong) AntiJaundiceView *overlayView;
@end

@implementation AntiJaundiceViewController

- (void)loadView {
    CGRect initialBounds = getEffectiveScreenBounds();
    AntiJaundiceContainerView *container = [[AntiJaundiceContainerView alloc] initWithFrame:initialBounds];
    container.backgroundColor = [UIColor clearColor];
    container.userInteractionEnabled = NO;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = container;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.view.userInteractionEnabled = NO;
    
    self.overlayView = [[AntiJaundiceView alloc] initWithFrame:self.view.bounds];
    self.overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overlayView.userInteractionEnabled = NO;
    [self.view addSubview:self.overlayView];
    
    reloadPreferences();
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (self.overlayView && !CGSizeEqualToSize(self.overlayView.bounds.size, self.view.bounds.size)) {
        self.overlayView.frame = self.view.bounds;
        self.overlayView.bounds = self.view.bounds;
        [self.overlayView updateGradientGeometry];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.overlayView && !CGSizeEqualToSize(self.overlayView.bounds.size, self.view.bounds.size)) {
        self.overlayView.frame = self.view.bounds;
        self.overlayView.bounds = self.view.bounds;
        [self.overlayView updateGradientGeometry];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    CGRect newBounds = CGRectMake(0, 0, size.width, size.height);
    self.view.frame = newBounds;
    self.view.bounds = newBounds;
    if (self.overlayView) {
        self.overlayView.frame = newBounds;
        self.overlayView.bounds = newBounds;
        [self.overlayView updateGradientGeometry];
    }
    
    if (coordinator) {
        [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            (void)context;
            CGRect animBounds = CGRectMake(0, 0, size.width, size.height);
            self.view.frame = animBounds;
            self.view.bounds = animBounds;
            if (self.overlayView) {
                self.overlayView.frame = animBounds;
                self.overlayView.bounds = animBounds;
                [self.overlayView updateGradientGeometry];
            }
        } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            (void)context;
            CGRect finalBounds = getEffectiveScreenBounds();
            if (self.view.window) {
                self.view.window.frame = finalBounds;
                self.view.window.bounds = finalBounds;
            }
            self.view.frame = finalBounds;
            self.view.bounds = finalBounds;
            if (self.overlayView) {
                self.overlayView.frame = finalBounds;
                self.overlayView.bounds = finalBounds;
                [self.overlayView updateGradientGeometry];
            }
        }];
    }
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

@end

@interface AntiJaundiceWindow : UIWindow
@end

@implementation AntiJaundiceWindow

- (void)commonInit {
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    self.windowLevel = UIWindowLevelStatusBar + 50.0;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene {
    self = [super initWithWindowScene:windowScene];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (BOOL)_ignoresHitTest {
    return YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return nil;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return NO;
}

- (BOOL)_canBecomeKeyWindow {
    return NO;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)_canAffectStatusBarAppearance {
    return NO;
}

- (BOOL)_shouldControlAutorotation {
    return YES;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect targetBounds = getEffectiveScreenBounds();
    if (!CGRectIsEmpty(targetBounds)) {
        if (!CGRectEqualToRect(self.bounds, targetBounds)) {
            self.bounds = targetBounds;
        }
        if (!CGRectEqualToRect(self.frame, targetBounds)) {
            self.frame = targetBounds;
        }
    }
    if (self.rootViewController && self.rootViewController.view) {
        if (!CGRectEqualToRect(self.rootViewController.view.frame, self.bounds)) {
            self.rootViewController.view.frame = self.bounds;
            self.rootViewController.view.bounds = self.bounds;
        }
    }
    if (gOverlayVC && gOverlayVC.overlayView) {
        if (!CGRectEqualToRect(gOverlayVC.overlayView.frame, self.bounds)) {
            gOverlayVC.overlayView.frame = self.bounds;
            gOverlayVC.overlayView.bounds = self.bounds;
            [gOverlayVC.overlayView updateGradientGeometry];
        }
    }
}

@end

static CGRect getEffectiveScreenBounds(void) {
    CGRect bounds = [UIScreen mainScreen].bounds;
    if (gOverlayWindow && gOverlayWindow.windowScene) {
        bounds = gOverlayWindow.windowScene.coordinateSpace.bounds;
    }
    
    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    if (gOverlayWindow && gOverlayWindow.windowScene) {
        orientation = gOverlayWindow.windowScene.interfaceOrientation;
    }
    if (orientation == UIInterfaceOrientationUnknown) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        orientation = [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
    }
    
    BOOL isLandscape = NO;
    if (UIInterfaceOrientationIsLandscape(orientation)) {
        isLandscape = YES;
    } else if (UIInterfaceOrientationIsPortrait(orientation)) {
        isLandscape = NO;
    } else {
        UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
        if (UIDeviceOrientationIsLandscape(deviceOrientation)) {
            isLandscape = YES;
        } else if (UIDeviceOrientationIsPortrait(deviceOrientation)) {
            isLandscape = NO;
        } else {
            isLandscape = (bounds.size.width > bounds.size.height);
        }
    }
    
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    if (isLandscape) {
        bounds.size.width = MAX(w, h);
        bounds.size.height = MIN(w, h);
    } else {
        bounds.size.width = MIN(w, h);
        bounds.size.height = MAX(w, h);
    }
    bounds.origin = CGPointZero;
    return bounds;
}

static NSDictionary *loadPrefsDict(void) {
    NSArray *paths = @[
        @"/var/mobile/Library/Preferences/com.ronci.antijaundice.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.ronci.antijaundice.plist"
    ];
    for (NSString *p in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
            if (d && [d count] > 0) return d;
        }
    }
    return nil;
}

static id readPrefValue(NSString *key, NSDictionary **diskDictPtr) {
    CFPropertyListRef val = CFPreferencesCopyAppValue((CFStringRef)key, CFSTR("com.ronci.antijaundice"));
    if (val) {
        return (__bridge_transfer id)val;
    }
    if (diskDictPtr) {
        if (!*diskDictPtr) {
            *diskDictPtr = loadPrefsDict();
        }
        if (*diskDictPtr && (*diskDictPtr)[key] != nil) {
            return (*diskDictPtr)[key];
        }
    }
    return nil;
}

static void reloadPreferences(void) {
    if (!gOverlayWindow || !gOverlayWindow.windowScene) {
        setupOverlayIfReady();
    }
    
    CFPreferencesAppSynchronize(CFSTR("com.ronci.antijaundice"));
    
    BOOL enabled = YES;
    CGFloat intensity = 0.08;
    CGFloat edgeOffset = 10.0;
    CGFloat bandWidth = 100.0;
    CGFloat colorHue = 50.0;
    NSInteger colorPreset = 0;
    
    NSDictionary *diskDict = nil;
    
    id enVal = readPrefValue(@"enabled", &diskDict);
    if (enVal != nil) {
        enabled = [enVal boolValue];
    }
    id intVal = readPrefValue(@"intensity", &diskDict);
    if (intVal != nil) {
        CGFloat raw = [intVal floatValue];
        // Settings slider is percentage: 0.1% to 20.0%. Normalize to 0.001 - 0.20.
        raw /= 100.0;
        if (raw < 0.001) raw = 0.001;
        if (raw > 0.20) raw = 0.20;
        intensity = raw;
    }
    id eoVal = readPrefValue(@"edgeOffset", &diskDict);
    if (eoVal != nil) {
        CGFloat raw = [eoVal floatValue];
        if (raw < 0.0) raw = 0.0;
        if (raw > 40.0) raw = 40.0;
        edgeOffset = round(raw);
    }
    id bwVal = readPrefValue(@"bandWidth", &diskDict);
    if (bwVal == nil) {
        bwVal = readPrefValue(@"borderWidth", &diskDict);
    }
    if (bwVal != nil) {
        CGFloat raw = [bwVal floatValue];
        if (raw < 50.0) raw = 50.0;
        if (raw > 250.0) raw = 250.0;
        bandWidth = round(raw);
    }
    
    id chVal = readPrefValue(@"colorHue", &diskDict);
    if (chVal != nil) {
        CGFloat raw = [chVal floatValue];
        if (raw < 0.0) raw = 0.0;
        if (raw > 100.0) raw = 100.0;
        colorHue = raw;
    } else {
        // Fallback for legacy colorPreset if colorHue not set yet
        id cpVal = readPrefValue(@"colorPreset", &diskDict);
        if (cpVal != nil) {
            colorPreset = [cpVal integerValue];
            if (colorPreset == 0) colorHue = 10.0;       // Cyan-blue
            else if (colorPreset == 1) colorHue = 35.0;  // Sky-blue
            else if (colorPreset == 2) colorHue = 60.0;  // Deep-blue
            else if (colorPreset == 3) colorHue = 90.0;  // Violet-blue
        }
    }
    
    if (gOverlayVC && gOverlayVC.overlayView) {
        gOverlayVC.overlayView.isFilterEnabled = enabled;
        gOverlayVC.overlayView.intensity = intensity;
        gOverlayVC.overlayView.edgeOffset = edgeOffset;
        gOverlayVC.overlayView.bandWidth = bandWidth;
        gOverlayVC.overlayView.colorHue = colorHue;
        gOverlayVC.overlayView.colorPreset = colorPreset;
        [gOverlayVC.overlayView updateGradientAppearance];
        [gOverlayVC.overlayView updateGradientGeometry];
    }
    if (gOverlayWindow) {
        gOverlayWindow.hidden = !enabled;
    }
    [CATransaction flush];
}

static void onPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    dispatch_async(dispatch_get_main_queue(), ^{
        setupOverlayIfReady();
        reloadPreferences();
        [CATransaction flush];
    });
}

static UIWindowScene *findActiveWindowScene(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    return ws;
                }
            }
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.windowScene && w.windowScene.activationState == UISceneActivationStateForegroundActive) {
                return w.windowScene;
            }
        }
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                return (UIWindowScene *)scene;
            }
        }
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.windowScene) {
                return w.windowScene;
            }
        }
#pragma clang diagnostic pop
    }
    return nil;
}

static CGRect gLastWindowBounds = { {0, 0}, {0, 0} };
static __weak UIWindowScene *gLastWindowScene = nil;

static void updateWindowFrames(void) {
    if (!gOverlayWindow) return;
    
    UIWindowScene *scene = findActiveWindowScene();
    CGRect screenBounds = getEffectiveScreenBounds();
    
    if (CGRectEqualToRect(gLastWindowBounds, screenBounds) && gLastWindowScene == scene && gOverlayWindow.windowScene == scene) {
        return; // Size and scene unchanged: zero work!
    }
    
    gLastWindowBounds = screenBounds;
    gLastWindowScene = scene;
    
    if (scene && (!gOverlayWindow.windowScene || gOverlayWindow.windowScene != scene)) {
        gOverlayWindow.windowScene = scene;
    }
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gOverlayWindow.frame = screenBounds;
    gOverlayWindow.bounds = screenBounds;
    if (gOverlayVC) {
        gOverlayVC.view.frame = screenBounds;
        gOverlayVC.view.bounds = screenBounds;
        if (gOverlayVC.overlayView) {
            gOverlayVC.overlayView.frame = screenBounds;
            gOverlayVC.overlayView.bounds = screenBounds;
            [gOverlayVC.overlayView updateGradientGeometry];
        }
    }
    [CATransaction commit];
}

static void setupOverlayIfReady(void) {
    UIWindowScene *targetScene = findActiveWindowScene();
    
    if (gOverlayWindow) {
        if (!gOverlayWindow.windowScene && targetScene) {
            gOverlayWindow.windowScene = targetScene;
        } else if (targetScene && gOverlayWindow.windowScene != targetScene && targetScene.activationState == UISceneActivationStateForegroundActive) {
            gOverlayWindow.windowScene = targetScene;
        }
        updateWindowFrames();
        return;
    }
    
    CGRect initialBounds = getEffectiveScreenBounds();
    if (targetScene) {
        gOverlayWindow = [[AntiJaundiceWindow alloc] initWithWindowScene:targetScene];
        gOverlayWindow.frame = initialBounds;
        gOverlayWindow.bounds = initialBounds;
    } else {
        gOverlayWindow = [[AntiJaundiceWindow alloc] initWithFrame:initialBounds];
    }
    
    gOverlayVC = [[AntiJaundiceViewController alloc] init];
    gOverlayWindow.rootViewController = gOverlayVC;
    if (@available(iOS 9.0, *)) {
        [gOverlayVC loadViewIfNeeded];
    } else {
        (void)gOverlayVC.view;
    }
    
    updateWindowFrames();
    NSLog(@"[AntiJaundice] Overlay window successfully initialized (scene: %@, bounds: %@)", targetScene, NSStringFromCGRect(initialBounds));
}

static void onSceneActivated(NSNotification *note) {
    (void)note;
    setupOverlayIfReady();
    reloadPreferences();
}

#pragma mark - Objective-C Method Hooking Utility

static void safeSwizzle(Class cls, SEL sel, IMP newImp, IMP *origImpOut) {
    if (!cls || !sel || !newImp || !origImpOut) return;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    
    BOOL added = class_addMethod(cls, sel, newImp, method_getTypeEncoding(method));
    if (added) {
        *origImpOut = method_getImplementation(method);
    } else {
        *origImpOut = method_setImplementation(method, newImp);
    }
}

static void hookInstanceMethod(Class cls, SEL sel, IMP newImp, IMP *origImpOut, const char *types) {
    (void)types;
    safeSwizzle(cls, sel, newImp, origImpOut);
}

#pragma mark - Screenshot Exclusion & Interception

static BOOL gOverlayHiddenForScreenshot = NO;
static uint64_t gScreenshotSeq = 0;

static void restoreOverlayAfterScreenshot(void) {
    if (!gOverlayHiddenForScreenshot) return;
    gOverlayHiddenForScreenshot = NO;
    
    BOOL enabled = YES;
    if (gOverlayVC && gOverlayVC.overlayView) {
        enabled = gOverlayVC.overlayView.isFilterEnabled;
        gOverlayVC.overlayView.hidden = NO;
    }
    if (gOverlayWindow) {
        gOverlayWindow.hidden = !enabled;
        gOverlayWindow.alpha = 1.0;
    }
    [CATransaction flush];
}

static void hideOverlayForScreenshot(void) {
    uint64_t seq = ++gScreenshotSeq;
    gOverlayHiddenForScreenshot = YES;
    
    if (gOverlayWindow) {
        gOverlayWindow.hidden = YES;
        gOverlayWindow.alpha = 0.0;
    }
    if (gOverlayVC && gOverlayVC.overlayView) {
        gOverlayVC.overlayView.hidden = YES;
    }
    [CATransaction flush];
    
    // Auto-restore after 0.5s if notification or completion did not fire
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gScreenshotSeq == seq && gOverlayHiddenForScreenshot) {
            restoreOverlayAfterScreenshot();
        }
    });
}

// 1. SSScreenCapturer - takeScreenshot
static void (*orig_SSScreenCapturer_takeScreenshot)(id, SEL) = NULL;
static void swizzled_SSScreenCapturer_takeScreenshot(id self, SEL _cmd) {
    NSLog(@"[AntiJaundice] SSScreenCapturer -takeScreenshot intercepted");
    hideOverlayForScreenshot();
    if (orig_SSScreenCapturer_takeScreenshot) {
        orig_SSScreenCapturer_takeScreenshot(self, _cmd);
    }
}

// 2. SSScreenCapturer - _preheatAndTakeScreenshotIfPossibleWithOptionsCollection:presentationOptions:appleInternalOptions:
static void (*orig_SSScreenCapturer_preheat)(id, SEL, id, id, id) = NULL;
static void swizzled_SSScreenCapturer_preheat(id self, SEL _cmd, id a1, id a2, id a3) {
    NSLog(@"[AntiJaundice] SSScreenCapturer _preheatAndTakeScreenshot intercepted");
    hideOverlayForScreenshot();
    if (orig_SSScreenCapturer_preheat) {
        orig_SSScreenCapturer_preheat(self, _cmd, a1, a2, a3);
    }
}

// 3. SBScreenshotManager - saveScreenshotsWithContext:completion:
static void (*orig_SBScreenshotManager_saveWithContext)(id, SEL, id, id) = NULL;
static void swizzled_SBScreenshotManager_saveWithContext(id self, SEL _cmd, id ctx, id completion) {
    NSLog(@"[AntiJaundice] SBScreenshotManager saveScreenshotsWithContext intercepted");
    hideOverlayForScreenshot();
    if (orig_SBScreenshotManager_saveWithContext) {
        orig_SBScreenshotManager_saveWithContext(self, _cmd, ctx, completion);
    }
}

// 4. SBScreenshotManager - saveScreenshotsWithCompletion:
static void (*orig_SBScreenshotManager_saveWithCompletion)(id, SEL, id) = NULL;
static void swizzled_SBScreenshotManager_saveWithCompletion(id self, SEL _cmd, id completion) {
    NSLog(@"[AntiJaundice] SBScreenshotManager saveScreenshotsWithCompletion intercepted");
    hideOverlayForScreenshot();
    if (orig_SBScreenshotManager_saveWithCompletion) {
        orig_SBScreenshotManager_saveWithCompletion(self, _cmd, completion);
    }
}

// 5. SBScreenshotManager - takeScreenshot
static void (*orig_SBScreenshotManager_takeScreenshot)(id, SEL) = NULL;
static void swizzled_SBScreenshotManager_takeScreenshot(id self, SEL _cmd) {
    NSLog(@"[AntiJaundice] SBScreenshotManager takeScreenshot intercepted");
    hideOverlayForScreenshot();
    if (orig_SBScreenshotManager_takeScreenshot) {
        orig_SBScreenshotManager_takeScreenshot(self, _cmd);
    }
}

// 6. SBScreenshotManager - saveScreenshots
static void (*orig_SBScreenshotManager_saveScreenshots)(id, SEL) = NULL;
static void swizzled_SBScreenshotManager_saveScreenshots(id self, SEL _cmd) {
    NSLog(@"[AntiJaundice] SBScreenshotManager saveScreenshots intercepted");
    hideOverlayForScreenshot();
    if (orig_SBScreenshotManager_saveScreenshots) {
        orig_SBScreenshotManager_saveScreenshots(self, _cmd);
    }
}

// 7. SBScreenFlash - flashWhiteWithCompletion:
static void (*orig_SBScreenFlash_flashWhiteWithCompletion)(id, SEL, id) = NULL;
static void swizzled_SBScreenFlash_flashWhiteWithCompletion(id self, SEL _cmd, id completion) {
    NSLog(@"[AntiJaundice] SBScreenFlash flashWhiteWithCompletion intercepted");
    hideOverlayForScreenshot();
    if (orig_SBScreenFlash_flashWhiteWithCompletion) {
        orig_SBScreenFlash_flashWhiteWithCompletion(self, _cmd, completion);
    }
}

// 8. SBScreenFlash - flashColor:withCompletion:
static void (*orig_SBScreenFlash_flashColorWithCompletion)(id, SEL, id, id) = NULL;
static void swizzled_SBScreenFlash_flashColorWithCompletion(id self, SEL _cmd, id color, id completion) {
    NSLog(@"[AntiJaundice] SBScreenFlash flashColorWithCompletion intercepted");
    hideOverlayForScreenshot();
    if (orig_SBScreenFlash_flashColorWithCompletion) {
        orig_SBScreenFlash_flashColorWithCompletion(self, _cmd, color, completion);
    }
}

// 9. SpringBoard - takeScreenshot
static void (*orig_SpringBoard_takeScreenshot)(id, SEL) = NULL;
static void swizzled_SpringBoard_takeScreenshot(id self, SEL _cmd) {
    NSLog(@"[AntiJaundice] SpringBoard takeScreenshot intercepted");
    hideOverlayForScreenshot();
    if (orig_SpringBoard_takeScreenshot) {
        orig_SpringBoard_takeScreenshot(self, _cmd);
    }
}

static BOOL gScreenshotHooksInstalled = NO;

static void installScreenshotHooks(void) {
    if (gScreenshotHooksInstalled) return;
    
    dlopen("/System/Library/PrivateFrameworks/ScreenshotServices.framework/ScreenshotServices", RTLD_NOW | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard", RTLD_NOW | RTLD_GLOBAL);
    
    int hooksCount = 0;
    
    Class scClass = NSClassFromString(@"SSScreenCapturer");
    if (scClass) {
        safeSwizzle(scClass, @selector(takeScreenshot), (IMP)swizzled_SSScreenCapturer_takeScreenshot, (IMP *)&orig_SSScreenCapturer_takeScreenshot);
        safeSwizzle(scClass, @selector(_preheatAndTakeScreenshotIfPossibleWithOptionsCollection:presentationOptions:appleInternalOptions:), (IMP)swizzled_SSScreenCapturer_preheat, (IMP *)&orig_SSScreenCapturer_preheat);
        hooksCount++;
    }
    
    Class smClass = NSClassFromString(@"SBScreenshotManager");
    if (smClass) {
        safeSwizzle(smClass, @selector(saveScreenshotsWithContext:completion:), (IMP)swizzled_SBScreenshotManager_saveWithContext, (IMP *)&orig_SBScreenshotManager_saveWithContext);
        safeSwizzle(smClass, @selector(saveScreenshotsWithCompletion:), (IMP)swizzled_SBScreenshotManager_saveWithCompletion, (IMP *)&orig_SBScreenshotManager_saveWithCompletion);
        safeSwizzle(smClass, @selector(takeScreenshot), (IMP)swizzled_SBScreenshotManager_takeScreenshot, (IMP *)&orig_SBScreenshotManager_takeScreenshot);
        safeSwizzle(smClass, @selector(saveScreenshots), (IMP)swizzled_SBScreenshotManager_saveScreenshots, (IMP *)&orig_SBScreenshotManager_saveScreenshots);
        hooksCount++;
    }
    
    Class sfClass = NSClassFromString(@"SBScreenFlash");
    if (sfClass) {
        safeSwizzle(sfClass, @selector(flashWhiteWithCompletion:), (IMP)swizzled_SBScreenFlash_flashWhiteWithCompletion, (IMP *)&orig_SBScreenFlash_flashWhiteWithCompletion);
        safeSwizzle(sfClass, @selector(flashColor:withCompletion:), (IMP)swizzled_SBScreenFlash_flashColorWithCompletion, (IMP *)&orig_SBScreenFlash_flashColorWithCompletion);
        hooksCount++;
    }
    
    Class sbClass = NSClassFromString(@"SpringBoard");
    if (sbClass) {
        safeSwizzle(sbClass, @selector(takeScreenshot), (IMP)swizzled_SpringBoard_takeScreenshot, (IMP *)&orig_SpringBoard_takeScreenshot);
        hooksCount++;
    }
    
    if (hooksCount > 0) {
        gScreenshotHooksInstalled = YES;
        NSLog(@"[AntiJaundice] %d screenshot classes hooked successfully for clean screenshot capture.", hooksCount);
    }
}




static void initSpringBoard(void) {
    NSLog(@"[AntiJaundice] Initializing AntiJaundice tweak for SpringBoard...");
    
    installScreenshotHooks();
    
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        onPrefsChanged,
        CFSTR("com.ronci.antijaundice/prefsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationUserDidTakeScreenshotNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        (void)note;
        NSLog(@"[AntiJaundice] UIApplicationUserDidTakeScreenshotNotification received");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            restoreOverlayAfterScreenshot();
        });
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        (void)note;
        if (!gScreenshotHooksInstalled) {
            installScreenshotHooks();
        }
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneDidActivateNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        onSceneActivated(note);
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        (void)note;
        setupOverlayIfReady();
        updateWindowFrames();
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        (void)note;
        updateWindowFrames();
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        (void)note;
        updateWindowFrames();
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        (void)note;
        installScreenshotHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            setupOverlayIfReady();
            reloadPreferences();
        });
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        installScreenshotHooks();
        setupOverlayIfReady();
        reloadPreferences();
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        installScreenshotHooks();
        setupOverlayIfReady();
        reloadPreferences();
    });
}

#pragma mark - Preferences Integration & Bidirectional Slider/Text Sync

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

static UISlider *getSliderFromView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UISlider class]]) return (UISlider *)view;
    if ([view respondsToSelector:@selector(control)]) {
        id c = [view performSelector:@selector(control)];
        if ([c isKindOfClass:[UISlider class]]) return (UISlider *)c;
    }
    for (UIView *sub in view.subviews) {
        UISlider *s = getSliderFromView(sub);
        if (s) return s;
    }
    return nil;
}

static UITextField *getTextFieldFromView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITextField class]]) return (UITextField *)view;
    if ([view respondsToSelector:@selector(textField)]) {
        id tf = [view performSelector:@selector(textField)];
        if ([tf isKindOfClass:[UITextField class]]) return (UITextField *)tf;
    }
    for (UIView *sub in view.subviews) {
        UITextField *tf = getTextFieldFromView(sub);
        if (tf) return tf;
    }
    return nil;
}

static void commitAntiJaundiceValue(UITableViewCell *cell, UITextField *textField) {
    if (!cell || !textField) return;
    
    id spec = nil;
    if ([cell respondsToSelector:@selector(specifier)]) {
        spec = [cell performSelector:@selector(specifier)];
    }
    if (!spec || ![spec respondsToSelector:@selector(propertyForKey:)]) return;
    
    NSString *defaults = [spec performSelector:@selector(propertyForKey:) withObject:@"defaults"];
    if (![defaults isEqualToString:@"com.ronci.antijaundice"]) return;
    
    NSString *key = [spec performSelector:@selector(propertyForKey:) withObject:@"key"];
    if (!key) return;
    
    CGFloat minVal = 0.0;
    CGFloat maxVal = 100.0;
    BOOL isFloat = NO;
    
    if ([key isEqualToString:@"edgeOffset"]) {
        minVal = 0.0;
        maxVal = 40.0;
        isFloat = NO;
    } else if ([key isEqualToString:@"bandWidth"]) {
        minVal = 50.0;
        maxVal = 250.0;
        isFloat = NO;
    } else if ([key isEqualToString:@"intensity"]) {
        minVal = 0.1;
        maxVal = 20.0;
        isFloat = YES;
    } else if ([key isEqualToString:@"colorHue"]) {
        minVal = 0.0;
        maxVal = 100.0;
        isFloat = NO;
    } else {
        return;
    }
    
    NSString *text = textField.text ?: @"";
    text = [text stringByReplacingOccurrencesOfString:@"," withString:@"."];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    CGFloat val = [text floatValue];
    if (val < minVal) val = minVal;
    if (val > maxVal) val = maxVal;
    
    if (isFloat) {
        textField.text = [NSString stringWithFormat:@"%.1f", val];
    } else {
        textField.text = [NSString stringWithFormat:@"%.0f", val];
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
    
    // 3. Post Darwin Notification immediately for live SpringBoard update
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.ronci.antijaundice/prefsChanged"),
        NULL,
        NULL,
        YES
    );
    
    // 4. Update the companion slider visually with animation
    UIResponder *responder = cell;
    UIViewController *parentVC = nil;
    UITableView *tableView = nil;
    while (responder) {
        if (!tableView && [responder isKindOfClass:[UITableView class]]) {
            tableView = (UITableView *)responder;
        }
        if (!parentVC && [responder isKindOfClass:[UIViewController class]]) {
            parentVC = (UIViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    
    if (tableView) {
        for (UITableViewCell *c in tableView.visibleCells) {
            if (c == cell) continue;
            if ([c respondsToSelector:@selector(specifier)]) {
                id s = [c performSelector:@selector(specifier)];
                if (s && [s respondsToSelector:@selector(propertyForKey:)]) {
                    if ([[s performSelector:@selector(propertyForKey:) withObject:@"defaults"] isEqualToString:@"com.ronci.antijaundice"] &&
                        [[s performSelector:@selector(propertyForKey:) withObject:@"key"] isEqualToString:key]) {
                        UISlider *slider = getSliderFromView(c);
                        if (slider) {
                            [slider setValue:val animated:YES];
                        }
                    }
                }
            }
        }
    }
    
    // 5. Update PSListController specifier model
    if (parentVC && [parentVC respondsToSelector:@selector(setPreferenceValue:specifier:)]) {
        [parentVC performSelector:@selector(setPreferenceValue:specifier:) withObject:numVal withObject:spec];
        
        NSString *sliderId = [NSString stringWithFormat:@"%@_slider", key];
        if ([parentVC respondsToSelector:@selector(specifierForID:)]) {
            id sliderSpec = [parentVC performSelector:@selector(specifierForID:) withObject:sliderId];
            if (sliderSpec) {
                [parentVC performSelector:@selector(setPreferenceValue:specifier:) withObject:numVal withObject:sliderSpec];
            }
        }
    }
}

static BOOL (*orig_textFieldShouldReturn)(id, SEL, UITextField *) = NULL;
static BOOL swizzled_textFieldShouldReturn(UITableViewCell *self, SEL _cmd, UITextField *textField) {
    [textField resignFirstResponder];
    commitAntiJaundiceValue(self, textField);
    if (orig_textFieldShouldReturn) {
        return orig_textFieldShouldReturn(self, _cmd, textField);
    }
    return YES;
}

static void (*orig_textFieldDidEndEditing)(id, SEL, UITextField *) = NULL;
static void swizzled_textFieldDidEndEditing(UITableViewCell *self, SEL _cmd, UITextField *textField) {
    commitAntiJaundiceValue(self, textField);
    if (orig_textFieldDidEndEditing) {
        orig_textFieldDidEndEditing(self, _cmd, textField);
    }
}

static void (*orig_refreshCellContentsWithSpecifier)(id, SEL, id) = NULL;
static void swizzled_refreshCellContentsWithSpecifier(UITableViewCell *self, SEL _cmd, id specifier) {
    if (orig_refreshCellContentsWithSpecifier) {
        orig_refreshCellContentsWithSpecifier(self, _cmd, specifier);
    }
    
    if (specifier && [specifier respondsToSelector:@selector(propertyForKey:)]) {
        NSString *defaults = [specifier performSelector:@selector(propertyForKey:) withObject:@"defaults"];
        if ([defaults isEqualToString:@"com.ronci.antijaundice"]) {
            NSString *key = [specifier performSelector:@selector(propertyForKey:) withObject:@"key"];
            UITextField *tf = getTextFieldFromView(self);
            if (tf) {
                tf.returnKeyType = UIReturnKeyDone;
                tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
                
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

static void (*orig_setPreferenceValue_specifier)(id, SEL, id, id) = NULL;
static void swizzled_setPreferenceValue_specifier(UIViewController *self, SEL _cmd, id value, id specifier) {
    if (orig_setPreferenceValue_specifier) {
        orig_setPreferenceValue_specifier(self, _cmd, value, specifier);
    }
    
    if (!specifier || ![specifier respondsToSelector:@selector(propertyForKey:)]) {
        return;
    }
    
    NSString *defaults = [specifier performSelector:@selector(propertyForKey:) withObject:@"defaults"];
    if (![defaults isEqualToString:@"com.ronci.antijaundice"]) {
        return;
    }
    
    NSString *key = [specifier performSelector:@selector(propertyForKey:) withObject:@"key"];
    if (!key || [key isEqualToString:@"enabled"]) {
        return;
    }
    
    // When slider changes, update the companion text field in real time
    if ([value respondsToSelector:@selector(floatValue)]) {
        CGFloat fVal = [value floatValue];
        
        UITableView *tv = nil;
        if ([self respondsToSelector:@selector(table)]) {
            tv = [self performSelector:@selector(table)];
        }
        if (!tv) {
            for (UIView *v in self.view.subviews) {
                if ([v isKindOfClass:[UITableView class]]) {
                    tv = (UITableView *)v;
                    break;
                }
            }
        }
        
        if (tv) {
            for (UITableViewCell *c in tv.visibleCells) {
                if ([c respondsToSelector:@selector(specifier)]) {
                    id cellSpec = [c performSelector:@selector(specifier)];
                    if (cellSpec && [cellSpec respondsToSelector:@selector(propertyForKey:)]) {
                        if ([[cellSpec performSelector:@selector(propertyForKey:) withObject:@"defaults"] isEqualToString:@"com.ronci.antijaundice"] &&
                            [[cellSpec performSelector:@selector(propertyForKey:) withObject:@"key"] isEqualToString:key]) {
                            
                            UITextField *tf = getTextFieldFromView(c);
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
}

static void initPreferences(void) {
    NSLog(@"[AntiJaundice] Initializing AntiJaundice hooks inside Preferences...");
    
    dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_NOW);
    
    Class editCellClass = NSClassFromString(@"PSEditTextCell");
    if (editCellClass) {
        hookInstanceMethod(editCellClass, @selector(textFieldShouldReturn:), (IMP)swizzled_textFieldShouldReturn, (IMP *)&orig_textFieldShouldReturn, "B@:@");
        hookInstanceMethod(editCellClass, @selector(textFieldDidEndEditing:), (IMP)swizzled_textFieldDidEndEditing, (IMP *)&orig_textFieldDidEndEditing, "v@:@");
        hookInstanceMethod(editCellClass, @selector(refreshCellContentsWithSpecifier:), (IMP)swizzled_refreshCellContentsWithSpecifier, (IMP *)&orig_refreshCellContentsWithSpecifier, "v@:@");
    }
    
    Class listCtrlClass = NSClassFromString(@"PSListController");
    if (listCtrlClass) {
        hookInstanceMethod(listCtrlClass, @selector(setPreferenceValue:specifier:), (IMP)swizzled_setPreferenceValue_specifier, (IMP *)&orig_setPreferenceValue_specifier, "v@:@@");
    }
    
    NSLog(@"[AntiJaundice] Preferences hooks installed successfully.");
}

#pragma clang diagnostic pop

__attribute__((constructor)) static void AntiJaundiceInit(void) {
    @autoreleasepool {
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
        NSString *procName = [[NSProcessInfo processInfo] processName];
        
        if ([bundleId isEqualToString:@"com.apple.springboard"]) {
            initSpringBoard();
        } else if ([bundleId isEqualToString:@"com.apple.Preferences"] ||
                   [procName isEqualToString:@"Preferences"]) {
            initPreferences();
        }
    }
}
