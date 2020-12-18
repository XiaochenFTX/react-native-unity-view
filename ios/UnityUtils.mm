#import "UnityUtils.h"


#include "RNUnityMessageHandler.h"
#include <csignal>
#include <UnityFramework/UnityFramework.h>


bool unity_inited = false;

int g_argc;
char** g_argv;

//void UnityInitTrampoline();

extern "C" void InitArgs(int argc, char* argv[])
{
    g_argc = argc;
    g_argv = argv;
}

extern "C" bool UnityIsInited()
{
    return unity_inited;
}

UnityFramework* UnityFrameworkLoad()
{
    NSString* bundlePath = nil;
    bundlePath = [[NSBundle mainBundle] bundlePath];
    bundlePath = [bundlePath stringByAppendingString: @"/Frameworks/UnityFramework.framework"];

    NSBundle* bundle = [NSBundle bundleWithPath: bundlePath];
    if ([bundle isLoaded] == false) [bundle load];

    UnityFramework* ufw = [bundle.principalClass getInstance];
    if (![ufw appController])
    {
        // unity is not initialized
        [ufw setExecuteHeader: &_mh_execute_header];
    }
    return ufw;
}

static NSHashTable* mUnityEventListeners = [NSHashTable weakObjectsHashTable];
static BOOL _isUnityReady = NO;

void OnUnityMessage(const char* message)
{
    for (id<UnityEventListener> listener in mUnityEventListeners) {
        [listener onMessage:[NSString stringWithUTF8String:message]];
    }
}

extern "C" void InitUnity()
{
    if (unity_inited) {
        return;
    }
    unity_inited = true;

    SetOnUnityMessage(OnUnityMessage);
    
    @autoreleasepool
    {
        id ufw = UnityFrameworkLoad();
        [ufw runEmbeddedWithArgc:g_argc argv:g_argv appLaunchOpts:nil];
    }
}

extern "C" void UnityPostMessage(NSString* gameObject, NSString* methodName, NSString* message)
{

    [UnityFramework.getInstance sendMessageToGOWithName:[gameObject UTF8String] functionName:[methodName UTF8String] message:[message UTF8String]];
}

extern "C" void UnityPauseCommand()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UnityFramework.getInstance pause:true];
    });
}

extern "C" void UnityResumeCommand()
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [UnityFramework.getInstance pause:false];
    });
}

@implementation UnityUtils

+ (BOOL)isUnityReady
{
    return _isUnityReady;
}

+ (void)handleAppStateDidChange:(NSNotification *)notification
{
    if (!_isUnityReady) {
        return;
    }

    UnityAppController* unityAppController = [UnityFramework.getInstance appController];

    UIApplication* application = [UIApplication sharedApplication];

    if ([notification.name isEqualToString:UIApplicationWillResignActiveNotification]) {
        [unityAppController applicationWillResignActive:application];
    } else if ([notification.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        [unityAppController applicationDidEnterBackground:application];
    } else if ([notification.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        [unityAppController applicationWillEnterForeground:application];
    } else if ([notification.name isEqualToString:UIApplicationDidBecomeActiveNotification]) {
        [unityAppController applicationDidBecomeActive:application];
    } else if ([notification.name isEqualToString:UIApplicationWillTerminateNotification]) {
        [unityAppController applicationWillTerminate:application];
    } else if ([notification.name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) {
        [unityAppController applicationDidReceiveMemoryWarning:application];
    }
    
}


+ (void)listenAppState
{
    for (NSString *name in @[UIApplicationDidBecomeActiveNotification,
                             UIApplicationDidEnterBackgroundNotification,
                             UIApplicationWillTerminateNotification,
                             UIApplicationWillResignActiveNotification,
                             UIApplicationWillEnterForegroundNotification,
                             UIApplicationDidReceiveMemoryWarningNotification]) {
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleAppStateDidChange:)
                                                     name:name
                                                   object:nil];
    }
}

+ (void)createPlayer:(void (^)(void))completed
{
    if (_isUnityReady) {
        completed();
        return;
    }
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UnityReady" object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification * _Nonnull note) {
        _isUnityReady = YES;
        completed();
    }];
    
    if (UnityIsInited()) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication* application = [UIApplication sharedApplication];
        
        // Always keep RN window in top
        application.keyWindow.windowLevel = UIWindowLevelNormal + 1;
        InitUnity();

        [UnityUtils listenAppState];
    });
}

+ (void)addUnityEventListener:(id<UnityEventListener>)listener
{
    [mUnityEventListeners addObject:listener];
}

+ (void)removeUnityEventListener:(id<UnityEventListener>)listener
{
    [mUnityEventListeners removeObject:listener];
}

+ (BOOL)application:(UIApplication *)application openURL:(nonnull NSURL *)url options:(nonnull NSDictionary<NSString *,id> *)options
{
    UnityAppController* unityAppController = [UnityFramework.getInstance appController];
    return [unityAppController application:application openURL:url options:options];
}

@end
