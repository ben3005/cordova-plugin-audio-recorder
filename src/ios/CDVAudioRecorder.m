#import "CDVAudioRecorder.h"

#define DOCUMENTS_FOLDER [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
#define DEGREES_TO_RADIANS(degrees)  ((M_PI * degrees)/ 180)
#define MEGA_BYTES (1000.0f * 1000.0f)
#define DEFAULT_MAX_UPLOAD (30.0f * MEGA_BYTES)
#define kTIMER_INTERVAL 0.20
#define NAVIGATION_BAR_HEIGHT 88

/************************************************************************************************************
 *      CDV Audio Navigation Controller
 ************************************************************************************************************/
@implementation CDVRecorderNavigationController

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return [self.topViewController supportedInterfaceOrientations];
}
#else
- (NSUInteger)supportedInterfaceOrientations
{
    return [self.topViewController supportedInterfaceOrientations];
}
#endif
@end

#ifndef DEV_PLUGING

/************************************************************************************************************
 *      CDVAudioRecorder - Initialisation point of the plugin, creates a
 *      Navigation Controller and Pushes the main audio recorder view controller on to it.
 ************************************************************************************************************/
@implementation CDVAudioRecorder

@synthesize inUse = _inUse;

- (void)pluginInitialize
{
    NSLog(@"CDVAudioRecorder - pluginInitialize");
    self.inUse = NO;
}

// ----------------------------------
// -- ENTRY POINT FROM JAVA SCRIPT --
// ----------------------------------
- (void)audioRecorder:(CDVInvokedUrlCommand*)command
{
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    NSLog(@"CDVAudioRecorder - (void)audioRecorder:(CDVInvokedUrlCommand*)command");

    NSString* callbackId = command.callbackId;
    NSDictionary* options = [command argumentAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    double maxupload = [[options objectForKey:@"maxupload"] doubleValue];
    maxupload = maxupload * MEGA_BYTES;
    maxupload = (maxupload == 0) ? DEFAULT_MAX_UPLOAD : maxupload;

    CDVPluginResult* result = nil;

    if (NSClassFromString(@"CDVRecorderViewController") == nil) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:AUDIO_NOT_SUPPORTED];
    } else if (self.inUse == YES) {
        result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:AUDIO_APPLICATION_BUSY];
    } else {
        CDVRecorderViewController *recorderViewController = [[CDVRecorderViewController alloc] initWithCommand:self maxUpload:maxupload callbackId:callbackId];
        [recorderViewController setModalPresentationStyle: UIModalPresentationFullScreen];
        CDVRecorderNavigationController* navController = [[CDVRecorderNavigationController alloc] initWithRootViewController:recorderViewController];
        [navController setModalPresentationStyle:UIModalPresentationFullScreen];
        self.inUse = YES;
        [self.viewController setModalPresentationStyle:UIModalPresentationFullScreen];
        [self.viewController presentViewController:navController animated:YES completion:nil];
    }

    if (result) {
        [self.commandDelegate sendPluginResult:result callbackId:callbackId];
    }
}

- (NSDictionary*)getMediaDictionaryFromPath:(NSString*)fullPath ofType:(NSString*)type
{
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSMutableDictionary* fileDict = [NSMutableDictionary dictionaryWithCapacity:5];

    CDVFile *fs = [self.commandDelegate getCommandInstance:@"File"];
    if(!fullPath)
        return nil;
    NSURL *fileURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://%@", fullPath]];
    NSURL *resolvedFileURL = [fileURL URLByResolvingSymlinksInPath];
    NSString *path = [resolvedFileURL path];

    CDVFilesystemURL *url = [fs fileSystemURLforLocalPath:path];

    [fileDict setObject:[fullPath lastPathComponent] forKey:@"name"];
    [fileDict setObject:fullPath forKey:@"fullPath"];
    if (url) {
        [fileDict setObject:[url absoluteURL] forKey:@"localURL"];
    }
    if (!type) {
        id command = [self.commandDelegate getCommandInstance:@"File"];
        if ([command isKindOfClass:[CDVFile class]]) {
            CDVFile* cdvFile = (CDVFile*)command;
            NSString* mimeType = [cdvFile getMimeTypeFromPath:fullPath];
            [fileDict setObject:(mimeType != nil ? (NSObject*)mimeType : [NSNull null]) forKey:@"type"];
        }
    }
    NSDictionary* fileAttrs = [fileMgr attributesOfItemAtPath:fullPath error:nil];
    [fileDict setObject:[NSNumber numberWithUnsignedLongLong:[fileAttrs fileSize]] forKey:@"size"];
    NSDate* modDate = [fileAttrs fileModificationDate];
    NSNumber* msDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970] * 1000];
    [fileDict setObject:msDate forKey:@"lastModifiedDate"];
    return fileDict;
}
@end

#endif

#pragma mark - ACTUAL VIEW CONTROLLER INSIDE PLUG IN - INTERFACE
/************************************************************************************************************
 *      AudioRecorder - ViewController for the Audio Recorder
 ************************************************************************************************************/
@interface CDVRecorderViewController ()
{
    NSString *_recorderFilePath;
    AVAudioRecorder *_recorder;
    BOOL _isRecording;
    BOOL _isPaused;
    BOOL _isSavingRecording;
    float _recMilli;
    int _recSeconds;
    int _recMinutes;
    int _recHours;
    NSTimer *_timer;
    NSTimer *_circleTimer;
    double _MaxRecSize;
    double _CurrentRecSize;

    NSData *_headerData;
    NSOutputStream *_outputStream;

    float _averagePower;
    float _peakPower;
    BOOL _micPermission;
    BOOL _idleTimerDisabled;
}

@property (nonatomic, retain) NSString *recorderFilePath;
@property (nonatomic, retain) AVAudioRecorder *recorder;
@property (nonatomic, retain) NSTimer *timer;
@property (nonatomic, retain) NSTimer *circleTimer;
@property (nonatomic, retain) NSData *headerData;
@property (nonatomic, retain) NSOutputStream *outputStream;
@property BOOL isRecording;
@property BOOL isPaused;
@property BOOL isSavingRecording;
@property float recMilli;
@property int recSeconds;
@property int recMinutes;
@property int recHours;
@property float averagePower;
@property float peakPower;
@property double MaxRecSize;
@property double CurrentRecSize;
@property BOOL micPermission;
@property BOOL idleTimerDisabled;

- (void)startRecording;
- (void)stopRecording;
- (void)saveRecording;
- (void)pauseRecording;
- (void)resumeRecording;
- (void)finishPlugin;
@end

/************************************************************************************************************
 *      AudioRecorder - ViewController for the Audio Recorder
 ************************************************************************************************************/
@implementation CDVRecorderViewController

@synthesize recorderButton = _recorderButton;
@synthesize saveCancelButton = _saveCancelButton;
@synthesize backButton = _backButton;
@synthesize timeElapsedLabel = _timeElapsedLabel;
@synthesize fileSizeLabel = _fileSizeLabel;
@synthesize maxFileSizeLabel = _maxFileSizeLabel;
@synthesize scrollView = _scrollView;
@synthesize controlsToolbar = _controlsToolbar;
@synthesize userFilterID = _userFilterID;
@synthesize viewSaving = _viewSaving;

@synthesize recorderFilePath = _recorderFilePath;
@synthesize recorder = _recorder;
@synthesize isRecording = _isRecording;
@synthesize isPaused = _isPaused;
@synthesize isSavingRecording = _isSavingRecording;
@synthesize recMilli = recMilli;
@synthesize recSeconds = _recSeconds;
@synthesize recMinutes = _recMinutes;
@synthesize recHours = _recHours;
@synthesize timer = _timer;
@synthesize MaxRecSize = _MaxRecSize;
@synthesize CurrentRecSize = _CurrentRecSize;

@synthesize headerData = _headerData;
@synthesize outputStream = _outputStream;

@synthesize averagePower = _averagePower;
@synthesize peakPower = _peakPower;
@synthesize subview = _subview;
@synthesize circle = _circle;
@synthesize container = _container;
@synthesize value = _value;
@synthesize currentState = _currentState;

@synthesize circlesView = _circlesView;

@synthesize circleTimer = _circleTimer;

@synthesize fadeColor = _fadeColor;
@synthesize lastCircleLayer = _lastCircleLayer;
@synthesize lastRingLayer = _lastRingLayer;
@synthesize lastBackgroundRingLayer = _lastBackgroundRingLayer;
@synthesize errorCode = _errorCode;
@synthesize callbackId = _callbackId;
@synthesize duration = _duration;
@synthesize isTimed = _isTimed;
@synthesize previousStatusBarStyle = _previousStatusBarStyle;
@synthesize micPermission = _micPermission;
@synthesize idleTimerDisabled = _idleTimerDisabled;

#ifndef DEV_PLUGING
@synthesize audioRecorderCommand = _audioRecorderCommand;
@synthesize pluginResult = _pluginResult;
#endif
@synthesize errorResultMessage = _errorResultMessage;

/* ~~~~~~~~~~ PLUGIN ~~~~~~~~~~~ */
#pragma mark - View entry point for our new view.
#ifndef DEV_PLUGING
- (id)initWithCommand:(CDVAudioRecorder *)theCommand maxUpload:(double)maxUpload callbackId:(NSString *)theCallbackId
{
    NSLog(@"CDVRecorderViewController - initWithCommand: %f", maxUpload);
    if ((self = [super init])) {
        self.errorResultMessage = @"";
        self.audioRecorderCommand = theCommand;
        self.MaxRecSize = maxUpload;
        self.CurrentRecSize = 0;
        self.recMilli = 0.0;
        self.recMinutes = 0;
        self.recHours = 0;
        self.callbackId = theCallbackId;
        self.errorCode = AUDIO_NO_MEDIA_FILES;
        self.isTimed = self.duration != nil;
        self.previousStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
        return self;
    }
    return nil;
}
#endif

#pragma mark - Finish up and exit Plugin
-(void)finishPlugin {
#ifndef DEV_PLUGING
    NSMutableDictionary *jSON = [[NSMutableDictionary alloc] init];
    NSDictionary* fileDict = [self.audioRecorderCommand getMediaDictionaryFromPath:self.recorderFilePath ofType:@"audio/wav"];
    if(fileDict)
    {
        if(fileDict)
            [jSON setObject:fileDict forKey:@"fileDetails"];
        [jSON setObject:[NSNumber numberWithInt: STATUS_SUCCESS_WITH_FILE] forKey:@"status"];
    }
    else
        [jSON setObject:[NSNumber numberWithInt: STATUS_SUCCESS_NO_FILE] forKey:@"status"];
    if(jSON)
        self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:jSON];
    NSLog(@"%@", jSON);
    [[self.audioRecorderCommand.viewController.presentedViewController presentingViewController] dismissViewControllerAnimated:YES completion:nil];
    if (!self.pluginResult) {
        self.pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageToErrorObject:(int)self.errorCode];
    }
    [self.audioRecorderCommand setInUse:NO];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
    [self.audioRecorderCommand.commandDelegate sendPluginResult:self.pluginResult callbackId:self.callbackId];

    if (IsAtLeastiOSVersion(@"7.0")) {
        [[UIApplication sharedApplication] setStatusBarStyle:self.previousStatusBarStyle];
    }
#endif
}

-(void)finishPlugin_Error {
#ifndef DEV_PLUGING
    [[self.audioRecorderCommand.viewController.presentedViewController presentingViewController] dismissViewControllerAnimated:YES completion:nil];
    [self.audioRecorderCommand setInUse:NO];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: self.errorResultMessage];
    [self.audioRecorderCommand.commandDelegate sendPluginResult:result callbackId:self.callbackId];
#endif
}

/* ~~~~~~~~~~ VIEW ~~~~~~~~~~~ */
#pragma mark - initWithNibName
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    BOOL iPad = ([[UIDevice currentDevice].model isEqualToString:@"iPad"]);
    nibNameOrNil = iPad ? @"CDVAudioRecorder~ipad" : @"CDVAudioRecorder";
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}

#pragma mark - View Methods
- (void)viewDidLoad
{
    [super viewDidLoad];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.idleTimerDisabled = [UIApplication sharedApplication].idleTimerDisabled;
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backgroundNotification:)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
    self.isRecording = NO;
    self.isPaused = NO;
    self.isSavingRecording = NO;
    self.recSeconds = 0;
    self.recMinutes = 0;
    self.recHours = 0;
    self.currentState = STATE_NOT_SET;
    NSString *maxSizeText = [NSString stringWithFormat:@"%f MB", self.MaxRecSize];
    [self.maxFileSizeLabel setText:maxSizeText];
    self.value = 0;
    self.segment = 0;
    self.currentState = STATE_NOT_SET;

    UIBarButtonItem *btnDone = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(backButtonPressed:)];
    self.navigationController.topViewController.navigationItem.leftBarButtonItem = btnDone;
    btnDone.enabled=TRUE;
    btnDone.style=UIBarButtonSystemItemDone;
    self.saveCancelButton.enabled = NO;
    [self drawPie];
    [self changeButtonState];
    [self checkPermission];
}

-(void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    CGRect screenRect = [[UIScreen mainScreen] applicationFrame];
    self.container.frame = CGRectMake(((screenRect.size.width / 2) - (self.container.frame.size.width / 2)),
                                      ((screenRect.size.height / 2) - (self.container.frame.size.height / 2)),
                                      self.container.frame.size.width,
                                      self.container.frame.size.height);
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self checkAvailableStorage];
}

-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [UIApplication sharedApplication].idleTimerDisabled = self.idleTimerDisabled;
}

#pragma mark - ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#pragma mark - Check available storage space
-(bool)isStorageAvailable
{
    uint64_t totalSpace = 0;
    uint64_t totalFreeSpace = 0;
    __autoreleasing NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    if (dictionary)
    {
       NSNumber *fileSystemSizeInBytes = [dictionary objectForKey: NSFileSystemSize];
       NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
      totalSpace = [fileSystemSizeInBytes unsignedLongLongValue];
      totalFreeSpace = [freeFileSystemSizeInBytes unsignedLongLongValue];
      return self.MaxRecSize > ((totalFreeSpace / 1024ll) / 1024ll);
    }
    return false;
}

#pragma mark - Check permission to use Microphone
-(void)checkPermission
{
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        if (granted) {
            self.micPermission = YES;
        }
        else {
            self.micPermission = NO;
        }
    }];
}

#pragma mark -
-(void) checkAvailableStorage
{
    if(![self isStorageAvailable])
    {
        UIAlertAction *resetAction = [UIAlertAction
                                      actionWithTitle:NSLocalizedString(@"OKAY", @"OKAY")
                                      style:UIAlertActionStyleDestructive
                                      handler:^(UIAlertAction *action)
                                      {
                                        self.errorResultMessage = STORAGE_LOW;
                                        [self finishPlugin_Error];
                                      }];
        UIAlertController *alertController = [UIAlertController
                                              alertControllerWithTitle:@"Low Storage!"
                                              message:@"You don't have enough storage space to record audio!!"
                                              preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:resetAction];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

#pragma mark -
-(void) adviseUserPermission
{
    UIAlertAction *resetAction = [UIAlertAction
                                  actionWithTitle:NSLocalizedString(@"OKAY", @"OKAY action")
                                  style:UIAlertActionStyleDestructive
                                  handler:^(UIAlertAction *action)
                                  {
                                  }];
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:@"Mic Permission Error"
                                          message:@"This app does not have permission to use your mic, please go to the settings app and allow permission !!"
                                          preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:resetAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark -
- (NSString*)resolveImageResource:(NSString*)resource
{
    NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
    BOOL isLessThaniOS4 = ([systemVersion compare:@"4.0" options:NSNumericSearch] == NSOrderedAscending);
    if (isLessThaniOS4) {
        NSString* iPadResource = [NSString stringWithFormat:@"%@.png", resource];
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad && [UIImage imageNamed:iPadResource]) {
            return iPadResource;
        } else {
            return [NSString stringWithFormat:@"%@.png", resource];
        }
    }
    return resource;
}

#pragma mark -
- (void)changeButtonState {

    switch(self.currentState)
    {
        case STATE_MAX_REACHED:
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateNormal];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateSelected];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateDisabled];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateHighlighted];

            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateNormal];
            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateSelected];
            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateDisabled];
            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateHighlighted];
            break;
        case STATE_PAUSED:
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/continue"]] forState:UIControlStateNormal];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/continue"]] forState:UIControlStateSelected];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/continue"]] forState:UIControlStateDisabled];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/continue"]] forState:UIControlStateHighlighted];
            break;
        case STATE_RECORDING:
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateNormal];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateSelected];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateDisabled];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/pause"]] forState:UIControlStateHighlighted];
            break;
        case STATE_SAVING:
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateNormal];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateSelected];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateDisabled];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateHighlighted];
            break;
        case STATE_NOT_SET:
        case STATE_STOPPED:
        default:
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateNormal];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateSelected];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateDisabled];
            [self.recorderButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/record"]] forState:UIControlStateHighlighted];

            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateNormal];
            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateSelected];
            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateDisabled];
            [self.saveCancelButton setImage:[UIImage imageNamed:[self resolveImageResource:@"CDVAudioRecorder.bundle/save"]] forState:UIControlStateHighlighted];
            break;
    }
}

#pragma mark -
- (void)performButtonAction
{
    switch(self.currentState)
    {
        case STATE_MAX_REACHED:
            self.saveCancelButton.enabled = YES;
            self.recorderButton.enabled = NO;
            break;
        case STATE_RECORDING:
            [self pauseRecording];
            self.currentState = STATE_PAUSED;
            self.saveCancelButton.enabled = YES;
            break;
        case STATE_PAUSED:
            if(self.CurrentRecSize < self.MaxRecSize)
            {
            	self.saveCancelButton.enabled = YES;
                [self resumeRecording];
                [self performSelector:@selector(ripples) withObject:nil afterDelay:0.1];
                self.currentState = STATE_RECORDING;
            }
            break;
        case STATE_SAVE:
            [self stopRecording];
            [self saveRecording];
            [self finishPlugin];
            self.saveCancelButton.enabled = NO;
            self.isRecording = NO;
            self.isPaused = NO;
            self.isSavingRecording = NO;
            self.recSeconds = 0;
            self.recMinutes = 0;
            self.recHours = 0;
            self.value = 0;
            self.currentState = STATE_SAVING;
            break;
        case STATE_SAVING:
            break;
        case STATE_EXIT:
            [self stopRecording];
            self.currentState = STATE_EXITING;
            self.saveCancelButton.enabled = NO;
            break;
        case STATE_EXITING:
            break;
        case STATE_NOT_SET:
        case STATE_STOPPED:
        default:
            if(self.CurrentRecSize < self.MaxRecSize)
            {
                [self startRecording];
                [self performSelector:@selector(ripples) withObject:nil afterDelay:0.1];
                self.currentState = STATE_RECORDING;
                self.saveCancelButton.enabled = YES;
            }
            break;
    }
    [self changeButtonState];
}
#define PROGRESS_BACKGROUND [UIColor colorWithRed: (92.0 / 255) green: (99.0 / 255) blue: (107.0 /255) alpha: 1.0].CGColor
#define PROGRESS_FOREGROUND [UIColor colorWithRed: (255.0 / 255) green: (255.0 / 255) blue: (255.0 /255) alpha: 1.0].CGColor
#define PROGRESS_FOREGROUND_WARNING [UIColor redColor].CGColor

#pragma mark -
-(void)drawPie
{
    CGFloat radius = MIN(self.circle.frame.size.width,self.circle.frame.size.height)/2;
    CGFloat inset  = 18;
    CAShapeLayer *backgroundring = [CAShapeLayer layer];
    backgroundring.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.circle.bounds, inset, inset) cornerRadius:radius-inset].CGPath;
    backgroundring.fillColor   = [UIColor clearColor].CGColor;
    backgroundring.strokeColor = PROGRESS_BACKGROUND;
    backgroundring.lineWidth   = 14; // Width circle for progress
    backgroundring.strokeStart = self.value;
    backgroundring.strokeEnd = 1.0;

    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.circle.bounds, inset, inset) cornerRadius:radius-inset].CGPath;
    ring.fillColor   = [UIColor clearColor].CGColor;
    ring.strokeColor = (self.value > 0.9f) ? PROGRESS_FOREGROUND_WARNING : PROGRESS_FOREGROUND;
    ring.lineWidth   = 14; // Width circle for progress
    ring.strokeStart = 0;
    ring.strokeEnd = self.value;

    if(self.lastRingLayer) {
        [self.lastRingLayer removeFromSuperlayer];
        self.lastRingLayer = nil;
    }
    if(self.lastBackgroundRingLayer) {
        [self.lastBackgroundRingLayer removeFromSuperlayer];
        self.lastBackgroundRingLayer = nil;
    }
    [self.circle.layer addSublayer:backgroundring];
    [self.circle.layer addSublayer:ring];

    self.lastRingLayer = ring;
    self.lastBackgroundRingLayer = backgroundring;
}

-(void)ripples
{
    BOOL canStop = NO;
    if(!self.circles)
    {
        CGFloat radius = 100.0;
        NSNumber *radiusObject = [[NSNumber alloc] initWithFloat:radius];
        self.circles = [[NSMutableArray alloc] initWithCapacity:10];
        [self.circles addObject:radiusObject];
    } else {
    	if(self.circles && [self.circles count] > 0) {
			NSNumber *current = [self.circles objectAtIndex:0];
			CGFloat radius = [current floatValue];
			radius += 3.0;
			if(radius > 160.0)
			{
				radius = 86.0;
				self.fadeColor = 1.0;
				canStop = YES;
			}
			[self.circles setObject:[NSNumber numberWithFloat:radius] atIndexedSubscript:0];

			CAShapeLayer *circleLayer = [CAShapeLayer layer];
			float centreX = (self.circlesView.frame.size.width / 2);
			float centreY = (self.circlesView.frame.size.height / 2);
			float width = self.circlesView.frame.size.width;
			float height = self.circlesView.frame.size.height;
			[circleLayer setBounds:CGRectMake(0, 0, width, height)];
			[circleLayer setPosition:CGPointMake(centreX, centreY)];
			UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(centreX, centreY) radius:radius startAngle:0 endAngle:DEGREES_TO_RADIANS(360) clockwise:YES];
			[circleLayer setPath:[path CGPath]];
			[circleLayer setFillColor:[UIColor blackColor].CGColor];
			if(self.fadeColor > 0.0)
				self.fadeColor -= 0.04;
			float value = self.fadeColor;
			[circleLayer setStrokeColor:[UIColor colorWithRed:value green:value blue:value alpha:1.0].CGColor];
			[circleLayer setLineWidth:20.0f];
			self.circlesView.hidden = NO;
			if(self.lastCircleLayer) {
				[self.lastCircleLayer removeFromSuperlayer];
				self.lastCircleLayer = nil;
			}
			[[self.circlesView layer] addSublayer:circleLayer];
			self.lastCircleLayer = circleLayer;
        }
    }
    if(self.currentState == STATE_RECORDING || (self.currentState == STATE_PAUSED && !canStop))
        [self performSelector:@selector(ripples) withObject:nil afterDelay:0.05];
}

-(void)backgroundNotification:(NSNotification *)notification
{
    if(self.currentState == STATE_RECORDING)
    {
        [self.circles removeAllObjects];
        self.circles = nil;
        [self performButtonAction];
        [self changeButtonState];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    return YES;
}

#pragma mark - Buttons
- (IBAction)recorderButtonPressed:(id)sender
{
    if(self.micPermission)
        [self performButtonAction];
    else
        [self adviseUserPermission];
}

- (IBAction)backButtonPressed:(id)sender {
    self.currentState = STATE_SAVE;
    [self performButtonAction];
}

-(IBAction)saveButtonPressed:(id)sender
{
    self.currentState = STATE_SAVE;
    [self performButtonAction];
}

#pragma mark - Stream Methods
- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    switch(eventCode) {
        case NSStreamEventHasSpaceAvailable:
        {
            if(stream == self.outputStream)
            {
                uint32_t length = (uint32_t)htonl([self.headerData length]);
                [self.outputStream write:[self.headerData bytes] maxLength:length];
                [self.outputStream close];
            }
            break;
        }
        case NSStreamEventNone:
        case NSStreamEventOpenCompleted:
        case NSStreamEventHasBytesAvailable:
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered:
        {
            break;
        }
    }
}

#pragma mark -
- (void) handleTimer: (NSTimer *)timer
{
    self.CurrentRecSize = [[NSFileManager defaultManager] attributesOfItemAtPath:[[NSURL fileURLWithPath:self.recorderFilePath] path] error:nil].fileSize;
    self.value = 1.0 * (self.CurrentRecSize / self.MaxRecSize);
    self.value = (self.value > 1.0) ? 1.0 : self.value;

    self.recMilli += kTIMER_INTERVAL;
    if(self.recMilli >= 1.0)
    {
        self.recMilli = 0;
        self.recSeconds++;
        if(self.recSeconds == 60){
            self.recSeconds=0;
            self.recMinutes++;
            if(self.recMinutes >= 60)
            {
                self.recHours++;
                self.recMinutes = 0;
            }
        }
        self.timeElapsedLabel.text = [NSString stringWithFormat:@"%0.2ld:%0.2ld:%0.2ld", (long)self.recHours, (long)self.recMinutes, (long)self.recSeconds];
        [self drawPie];
    }
    if((self.recorder && self.recorder.recording && self.CurrentRecSize >= self.MaxRecSize))
        [self endRecording];
}

#pragma mark -
-(void) audioPermssionError
{
    self.errorResultMessage = MIC_NO_PERMISSION;
    [self finishPlugin_Error];
}

-(void) audioErrorWithTitle: (NSString *)title andMessage: message
{
}

#pragma mark -
- (void)startRecording {
    // Permission only required for iOS7 and up.
    if([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0)
    {
        __block BOOL permissionGranted = NO;
        // Check Microphone Permissions
        if([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)])
        {
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                if (granted) {
                    permissionGranted = YES;
                }
                else {
                    [self audioPermssionError];
                }
            }];
        }
        if(!permissionGranted)
        {
            return;
        }
    }
    self.isRecording = YES;
    self.isPaused = NO;
    self.recSeconds = 0;
    self.recMinutes = 0;

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    NSError *err = nil;
    [audioSession setCategory :AVAudioSessionCategoryPlayAndRecord error:&err];
    if(err){
        NSString *title = @"Microphone Error !";
        NSString *messaage = [NSString stringWithFormat: @"Error during microphone use:\nerror code: %ld.\n%@", (long)[err code], [[err userInfo] description] ];
        [self audioErrorWithTitle: title andMessage: messaage];
        return;
    }
    [audioSession setActive:YES error:&err];
    err = nil;
    if(err){
        NSString *title = @"Microphone Error !";
        NSString *message = [NSString stringWithFormat: @"Error during microphone use:\nerror code: %ld.\n%@", (long)[err code], [[err userInfo] description] ];
        [self audioErrorWithTitle: title andMessage: message];
        return;
    }

    NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];

    [recordSetting setValue :[NSNumber numberWithInt:kAudioFormatLinearPCM] forKey:AVFormatIDKey];
    [recordSetting setValue :[NSNumber numberWithFloat:16000.0] forKey:AVSampleRateKey];

    [recordSetting setValue :[NSNumber numberWithInt: 1] forKey:AVNumberOfChannelsKey];
    [recordSetting setValue :[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
    [recordSetting setValue :[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
    [recordSetting setValue :[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];

    CFUUIDRef uuid = CFUUIDCreate(NULL);
    CFStringRef uuidString = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    NSString *uniqueFileName = [NSString stringWithFormat:@"%@%@", @"_ev", (__bridge NSString *)uuidString];
    CFRelease(uuidString);

    NSArray *myPathList = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *myPath = [myPathList  objectAtIndex:0];

    NSString *uniquePNGname = [NSString stringWithFormat:@"/%@.wav",uniqueFileName];

    myPath = [myPath stringByAppendingPathComponent:uniquePNGname];

    self.recorderFilePath = myPath;

    NSURL *url = [NSURL fileURLWithPath:self.recorderFilePath];
    err = nil;
    self.recorder = [[ AVAudioRecorder alloc] initWithURL:url
                                                 settings:recordSetting
                                                    error:&err];
    if(!self.recorder)
    {
        return;
    }
    self.subview = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 1500.0f, self.scrollView.frame.size.height)];
    [self.scrollView addSubview:self.subview];

    [self.recorder setDelegate:self];
    [self.recorder prepareToRecord];
    self.recorder.meteringEnabled = NO;

    // Permission only required for iOS7 and up.
    if([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0)
    {
        __block BOOL permissionGranted = NO;
        if([[AVAudioSession sharedInstance] respondsToSelector:@selector(requestRecordPermission:)])
        {
            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
                if (granted) {
                    permissionGranted = YES;
                }
                else {
                    [self audioPermssionError];
                }
            }];
        }
        if(!permissionGranted)
        {
            return;
        }
    }
    [self.recorder record];
    self.timer = [NSTimer scheduledTimerWithTimeInterval: kTIMER_INTERVAL
                                                  target: self
                                                selector: @selector(handleTimer:)
                                                userInfo: nil
                                                 repeats: YES];
    [self.timer fire];
}

- (void)endRecording
{
    self.isRecording = NO;
    [self.timer invalidate];
    [self.recorder stop];
    self.value = 1.0;
    [self drawPie];
    self.timeElapsedLabel.text = [NSString stringWithFormat:@"%0.2ld:%0.2ld:%0.2ld", (long)self.recHours, (long)self.recMinutes, (long)self.recSeconds];
    self.circlesView.hidden = YES;
    if(self.circles)
        [self.circles removeAllObjects];
    if(self.lastCircleLayer)
        [self.lastCircleLayer removeFromSuperlayer];
    self.currentState = STATE_MAX_REACHED;
    [self performButtonAction];
}

- (void)stopRecording
{
    self.isRecording = NO;
    [self.timer invalidate];
    [self.recorder stop];
    self.currentState = STATE_STOPPED;
    [self changeButtonState];
    if(self.lastCircleLayer)
        [self.lastCircleLayer removeFromSuperlayer];
}

-(void)pauseRecording
{
    [self.timer invalidate];
    self.timer = nil;
    [self.recorder pause];
    self.isPaused = YES;
}

- (void)resumeRecording
{
    if(self.isPaused)
    {
        if(self.recorder && ![self.recorder isRecording])
        {
            self.timer = [NSTimer scheduledTimerWithTimeInterval: kTIMER_INTERVAL
                                                          target: self
                                                        selector: @selector(handleTimer:)
                                                        userInfo: nil
                                                         repeats: YES];
            [self.recorder record];
            self.isPaused = NO;
            [self.timer fire];
        }
    }
}

#pragma mark -
-(void)saveRecording
{
    if(self.recorderFilePath)
    {
        NSURL *RecordingPath = [NSURL fileURLWithPath:self.recorderFilePath];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[RecordingPath path] error:NULL];
        unsigned long long fileSize = [attributes fileSize]; // in bytes
        unsigned long long totalAudioLen = 0;
        unsigned long long totalDataLen = 0;
        long longSampleRate = 16000.0;
        int channels = 1;
        long byteRate = 16 * 16000.0 * channels/8;

        totalAudioLen = fileSize - 44;
        totalDataLen = fileSize;

        Byte *header = (Byte*)malloc(44);
        header[0] = 'R';  // RIFF/WAVE header
        header[1] = 'I';
        header[2] = 'F';
        header[3] = 'F';
        header[4] = (Byte) (totalDataLen & 0xff);
        header[5] = (Byte) ((totalDataLen >> 8) & 0xff);
        header[6] = (Byte) ((totalDataLen >> 16) & 0xff);
        header[7] = (Byte) ((totalDataLen >> 24) & 0xff);
        header[8] = 'W';
        header[9] = 'A';
        header[10] = 'V';
        header[11] = 'E';
        header[12] = 'f';  // 'fmt ' chunk
        header[13] = 'm';
        header[14] = 't';
        header[15] = ' ';
        header[16] = 16;  // 4 bytes: size of 'fmt ' chunk
        header[17] = 0;
        header[18] = 0;
        header[19] = 0;
        header[20] = 1;  // format = 1
        header[21] = 0;
        header[22] = (Byte) channels;
        header[23] = 0;
        header[24] = (Byte) (longSampleRate & 0xff);
        header[25] = (Byte) ((longSampleRate >> 8) & 0xff);
        header[26] = (Byte) ((longSampleRate >> 16) & 0xff);
        header[27] = (Byte) ((longSampleRate >> 24) & 0xff);
        header[28] = (Byte) (byteRate & 0xff);
        header[29] = (Byte) ((byteRate >> 8) & 0xff);
        header[30] = (Byte) ((byteRate >> 16) & 0xff);
        header[31] = (Byte) ((byteRate >> 24) & 0xff);
        header[32] = (Byte) (2 * 8 / 8);  // block align
        header[33] = 0;
        header[34] = 16;  // bits per sample
        header[35] = 0;
        header[36] = 'd';
        header[37] = 'a';
        header[38] = 't';
        header[39] = 'a';
        header[40] = (Byte) (totalAudioLen & 0xff);
        header[41] = (Byte) ((totalAudioLen >> 8) & 0xff);
        header[42] = (Byte) ((totalAudioLen >> 16) & 0xff);
        header[43] = (Byte) ((totalAudioLen >> 24) & 0xff);

        self.headerData = [NSData dataWithBytes:header length:44];
        free(header);
        self.outputStream = [NSOutputStream outputStreamToFileAtPath:[RecordingPath path] append:NO];
    }
}

#pragma mark -
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *) aRecorder successfully:(BOOL)flag
{
}

#pragma mark - Orientation Methods
- (BOOL)shouldAutorotate
{
    return YES;
}
@end
