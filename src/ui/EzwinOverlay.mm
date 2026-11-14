#include "ui/EzwinMenu.h"
#include <TargetConditionals.h>

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#include "imgui.h"
#include "imgui_impl_metal.h"
#include <float.h>
#include <math.h>

@interface EzwinOverlay : MTKView <MTKViewDelegate, UIKeyInput>
@property(nonatomic, strong) id<MTLCommandQueue> commands;
@property(nonatomic, assign) ImGuiContext *imgui;
@property(nonatomic) CFTimeInterval lastFrame;
@property(nonatomic, strong) UIButton *menuButton;
@property(nonatomic, weak) UIWindow *previousKeyWindow;
@end

@implementation EzwinOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame device:MTLCreateSystemDefaultDevice()];
    if (!self || !self.device) return nil;
    self.commands = [self.device newCommandQueue];
    if (!self.commands) return nil;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.clearColor = MTLClearColorMake(0, 0, 0, 0);
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.preferredFramesPerSecond = 60;
    self.multipleTouchEnabled = NO;
    ImGuiContext *previous = ImGui::GetCurrentContext();
    IMGUI_CHECKVERSION();
    self.imgui = ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = nullptr;
    io.LogFilename = nullptr;
    io.ConfigWindowsMoveFromTitleBarOnly = true;
    io.KeyMap[ImGuiKey_Backspace] = 8;
    io.KeyMap[ImGuiKey_Enter] = 13;
    ImFontConfig font; font.FontDataOwnedByAtlas = false;
    NSData *fontData = EzwinMenuFontData();
    if (!io.Fonts->AddFontFromMemoryTTF((void *)fontData.bytes, (int)fontData.length, 24, &font))
        io.Fonts->AddFontDefault();
    EzwinApplyMenuStyle();
    bool rendererReady = ImGui_ImplMetal_Init(self.device);
    ImGui::SetCurrentContext(previous);
    if (!rendererReady) return nil;
    self.delegate = self;
    self.menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.menuButton.frame = CGRectMake(12, 12, 76, 38);
    self.menuButton.backgroundColor = [UIColor colorWithRed:.12 green:.18 blue:.3 alpha:.95];
    self.menuButton.layer.cornerRadius = 12;
    self.menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.menuButton setTitle:@"EZWIN" forState:UIControlStateNormal];
    [self.menuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveButton:)]];
    [self addSubview:self.menuButton];
    EzwinInitializeMenu();
    EzwinStartRuntime();
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets inset = self.safeAreaInsets;
    CGPoint center = self.menuButton.center;
    center.x = fmax(inset.left + 38, fmin(center.x, self.bounds.size.width - inset.right - 38));
    center.y = fmax(inset.top + 19, fmin(center.y, self.bounds.size.height - inset.bottom - 19));
    self.menuButton.center = center;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (EzwinMenuVisible()) return [super pointInside:point withEvent:event];
    return CGRectContainsPoint(self.menuButton.frame, point);
}
- (void)toggleMenu {
    EzwinSetMenuVisible(!EzwinMenuVisible());
    if (!EzwinMenuVisible()) {
        [self resignFirstResponder];
        [self.previousKeyWindow makeKeyWindow];
        ImGuiContext *previous = ImGui::GetCurrentContext();
        ImGui::SetCurrentContext(self.imgui); ImGui::GetIO().MouseDown[0] = false;
        ImGui::SetCurrentContext(previous);
    }
}
- (void)moveButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGPoint center = self.menuButton.center;
    self.menuButton.center = CGPointMake(center.x + translation.x, center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self];
    [self setNeedsLayout];
}
- (void)updateTouch:(NSSet<UITouch *> *)touches down:(BOOL)down {
    UITouch *touch = touches.anyObject;
    if (!touch) return;
    CGPoint location = [touch locationInView:self];
    ImGuiContext *previous = ImGui::GetCurrentContext();
    ImGui::SetCurrentContext(self.imgui);
    ImGuiIO &io = ImGui::GetIO();
    io.MousePos = ImVec2(location.x, location.y); io.MouseDown[0] = down;
    ImGui::SetCurrentContext(previous);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)event; [self updateTouch:touches down:YES]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)event; [self updateTouch:touches down:YES]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)event; [self updateTouch:touches down:NO]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { (void)event; [self updateTouch:touches down:NO]; }
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return YES; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (void)insertText:(NSString *)text {
    ImGuiContext *previous = ImGui::GetCurrentContext(); ImGui::SetCurrentContext(self.imgui);
    ImGui::GetIO().AddInputCharactersUTF8(text.UTF8String);
    ImGui::SetCurrentContext(previous);
}
- (void)deleteBackward {
    ImGuiContext *previous = ImGui::GetCurrentContext(); ImGui::SetCurrentContext(self.imgui);
    ImGui::GetIO().KeysDown[8] = true;
    ImGui::SetCurrentContext(previous);
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size { (void)view; (void)size; }
- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        MTLRenderPassDescriptor *pass = view.currentRenderPassDescriptor;
        id<CAMetalDrawable> drawable = view.currentDrawable;
        if (!pass || !drawable || !self.imgui) return;
        ImGuiContext *previous = ImGui::GetCurrentContext(); ImGui::SetCurrentContext(self.imgui);
        ImGuiIO &io = ImGui::GetIO();
        CGSize size = self.bounds.size;
        io.DisplaySize = ImVec2(size.width, size.height);
        io.DisplayFramebufferScale = ImVec2(size.width > 0 ? self.drawableSize.width / size.width : 1,
            size.height > 0 ? self.drawableSize.height / size.height : 1);
        CFTimeInterval now = CACurrentMediaTime();
        io.DeltaTime = self.lastFrame > 0 ? fminf((float)(now - self.lastFrame), .1f) : 1.0f / 60;
        self.lastFrame = now;
        ImGui_ImplMetal_NewFrame(pass); ImGui::NewFrame();
        UIEdgeInsets inset = self.safeAreaInsets;
        ImGuiViewport *viewport = ImGui::GetMainViewport();
        viewport->WorkPos = ImVec2(inset.left, inset.top);
        viewport->WorkSize = ImVec2(size.width - inset.left - inset.right, size.height - inset.top - inset.bottom);
        EzwinDrawMenu(size.width, size.height);
        self.menuButton.hidden = EzwinMenuVisible();
        EzwinRenderESPWithImGui(ImGui::GetBackgroundDrawList(), io.FontDefault, nullptr, (int64_t)(now * 1e9));
        ImGui::Render();
        io.KeysDown[8] = false;
        BOOL keyboard = EzwinMenuVisible() && io.WantTextInput;
        if (keyboard && !self.isFirstResponder) {
            for (UIWindow *window in self.window.windowScene.windows)
                if (window.isKeyWindow && window != self.window) self.previousKeyWindow = window;
            [self.window makeKeyWindow]; [self becomeFirstResponder];
        } else if (!keyboard && self.isFirstResponder) {
            [self resignFirstResponder]; [self.previousKeyWindow makeKeyWindow];
        }
        id<MTLCommandBuffer> command = [self.commands commandBuffer];
        id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), command, encoder);
        [encoder endEncoding]; [command presentDrawable:drawable]; [command commit];
        ImGui::SetCurrentContext(previous);
    }
}
- (void)dealloc {
    if (self.imgui) {
        ImGuiContext *previous = ImGui::GetCurrentContext(); ImGui::SetCurrentContext(self.imgui);
        ImGui_ImplMetal_Shutdown(); ImGui::DestroyContext(self.imgui);
        ImGui::SetCurrentContext(previous == self.imgui ? nullptr : previous);
    }
}
@end

@interface EzwinOverlayWindow : UIWindow
@end
@implementation EzwinOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    EzwinOverlay *view = (EzwinOverlay *)self.rootViewController.view;
    if (!EzwinMenuVisible() && ![hit isDescendantOfView:view.menuButton]) return nil;
    return hit;
}
@end

static EzwinOverlay *overlay;
static EzwinOverlayWindow *overlayWindow;
static __weak UIWindow *gameplayWindow;
@interface EzwinOverlayController : UIViewController
@end
@implementation EzwinOverlayController
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return gameplayWindow.rootViewController ? gameplayWindow.rootViewController.supportedInterfaceOrientations : UIInterfaceOrientationMaskAll;
}
- (BOOL)prefersStatusBarHidden { return YES; }
@end

static void attachOverlay(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindowScene *targetScene = nil;
    UIWindow *target = nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window == overlayWindow || window.hidden || window.windowLevel != UIWindowLevelNormal || !window.rootViewController) continue;
            if (!target || window.isKeyWindow) { target = window; targetScene = (UIWindowScene *)scene; }
            if (window.isKeyWindow) break;
        }
        if (targetScene) break;
    }
    if (!targetScene) { overlayWindow.hidden = YES; return; }
    gameplayWindow = target;
    if (!overlay) overlay = [[EzwinOverlay alloc] initWithFrame:targetScene.coordinateSpace.bounds];
    if (!overlay) return;
    if (!overlayWindow || overlayWindow.windowScene != targetScene) {
        overlayWindow.hidden = YES;
        overlayWindow = [[EzwinOverlayWindow alloc] initWithWindowScene:targetScene];
        EzwinOverlayController *controller = [EzwinOverlayController new];
        controller.view = overlay;
        overlayWindow.rootViewController = controller;
        overlayWindow.windowLevel = UIWindowLevelNormal + 1;
        overlayWindow.backgroundColor = UIColor.clearColor;
    }
    overlayWindow.frame = targetScene.coordinateSpace.bounds;
    overlayWindow.alpha = overlay.alpha = 1;
    overlayWindow.hidden = NO; overlay.hidden = NO; overlay.paused = NO;
    if (overlayWindow.isKeyWindow && !overlay.isFirstResponder) [target makeKeyWindow];
    [overlay setNeedsLayout];
}
void EzwinStartOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSArray<NSNotificationName> *events = @[UIApplicationDidBecomeActiveNotification,
                UIWindowDidBecomeKeyNotification, UIWindowDidBecomeVisibleNotification, UISceneDidActivateNotification];
            for (NSNotificationName name in events)
                [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) { if (note.object != overlayWindow) attachOverlay(); }];
            // Scene/window replacement can happen without making another window key.
            NSTimer *repair = [NSTimer timerWithTimeInterval:.5 repeats:YES block:^(NSTimer *timer) {
                (void)timer; attachOverlay();
            }];
            [[NSRunLoop mainRunLoop] addTimer:repair forMode:NSRunLoopCommonModes];
        });
        attachOverlay();
    });
}
#else
void EzwinStartOverlay(void) { }
#endif
