//
//  ViewController.m
//  kxmovieapp
//
//  Created by Kolyvan on 11.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import "KxMovieViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import "KxMovieDecoder.h"
#import "KxAudioManager.h"
#import "KxMovieGLView.h"
#import "VideoCacheManager.h"
#import "CommentTextLayer.h"
#import "NicoCommentUtil.h"
#import "FontAwesomeKit/FAKFontAwesome.h"

NSString * const KxMovieParameterMinBufferedDuration = @"KxMovieParameterMinBufferedDuration";
NSString * const KxMovieParameterMaxBufferedDuration = @"KxMovieParameterMaxBufferedDuration";
NSString * const KxMovieParameterDisableDeinterlacing = @"KxMovieParameterDisableDeinterlacing";

NSString * const KxMovieParameterVideoInfo      = @"KxMovieParameterVideoInfo";
NSString * const KxMovieParameterDecodeDuration = @"KxMovieParameterDecodeDuration";


////////////////////////////////////////////////////////////////////////////////

static NSString * formatTimeInterval(CGFloat seconds, BOOL isLeft)
{
    seconds = MAX(0, seconds);
    
    NSInteger s = seconds;
    NSInteger m = s / 60;
//    NSInteger h = m / 60;
    
    s = s % 60;
//    m = m % 60;
    
    return [NSString stringWithFormat:@"%@%ld:%0.2ld", isLeft ? @"-" : @"", m, s];
}



@implementation UIImage (imageNamedWithColor)

+ (UIImage*)imageNamed:(NSString*)name withColor:(UIColor*)color {
   UIImage *img = [UIImage imageNamed:name];
   UIGraphicsBeginImageContextWithOptions(img.size, NO, [UIScreen mainScreen].scale);

   CGContextRef context = UIGraphicsGetCurrentContext();

   [color setFill];

   CGContextTranslateCTM(context, 0, img.size.height);
   CGContextScaleCTM(context, 1.0, -1.0);

   CGContextSetBlendMode(context, kCGBlendModeMultiply);
   CGRect rect = CGRectMake(0, 0, img.size.width, img.size.height);
   CGContextDrawImage(context, rect, img.CGImage);

   CGContextClipToMask(context, rect, img.CGImage);
   CGContextAddRect(context, rect);
   CGContextDrawPath(context, kCGPathFill);

   UIImage *coloredImg = UIGraphicsGetImageFromCurrentImageContext();
   UIGraphicsEndImageContext();

   return coloredImg;
}

@end


////////////////////////////////////////////////////////////////////////////////

@interface HudView : UIView
@end

@implementation HudView
//- (void)layoutSubviews
//{
//    NSArray * layers = self.layer.sublayers;
//    if (layers.count > 0) {        
//        CALayer *layer = layers[0];
//        layer.frame = self.bounds;
//    }
//}
@end

////////////////////////////////////////////////////////////////////////////////

enum {

    KxMovieInfoSectionGeneral,
    KxMovieInfoSectionVideo,
    KxMovieInfoSectionAudio,
    KxMovieInfoSectionSubtitles,
    KxMovieInfoSectionMetadata,    
    KxMovieInfoSectionCount,
};

enum {

    KxMovieInfoGeneralFormat,
    KxMovieInfoGeneralBitrate,
    KxMovieInfoGeneralCount,
};

////////////////////////////////////////////////////////////////////////////////

static NSMutableDictionary * gHistory;

//#define LOCAL_MIN_BUFFERED_DURATION   0.2
//#define LOCAL_MAX_BUFFERED_DURATION   0.4
#define LOCAL_MIN_BUFFERED_DURATION   1.0
#define LOCAL_MAX_BUFFERED_DURATION   3.0
//#define LOCAL_MIN_BUFFERED_DURATION   8.0
//#define LOCAL_MAX_BUFFERED_DURATION   15.0
#define NETWORK_MIN_BUFFERED_DURATION 3.0
#define NETWORK_MAX_BUFFERED_DURATION 5.0
//#define NETWORK_MIN_BUFFERED_DURATION 8.0
//#define NETWORK_MAX_BUFFERED_DURATION 15.0

@interface KxMovieViewController () {

    KxMovieDecoder      *_decoder;    
    dispatch_queue_t    _dispatchQueue;
    NSMutableArray      *_videoFrames;
    NSMutableArray      *_audioFrames;
    NSMutableArray      *_subtitles;
    NSData              *_currentAudioFrame;
    NSUInteger          _currentAudioFramePos;
    CGFloat             _moviePosition;
    BOOL                _disableUpdateHUD;
    NSTimeInterval      _tickCorrectionTime;
    NSTimeInterval      _tickCorrectionPosition;
    NSUInteger          _tickCounter;
    BOOL                _fullscreen;
    BOOL                _hiddenHUD;
    BOOL                _fitMode;
    BOOL                _infoMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;

    KxMovieGLView       *_glView;
    UIImageView         *_imageView;
    HudView             *_topHUD;
    UIView              *_bottomHUD;
    VideoSeekSlider     *_progressSlider;
    MPVolumeView        *_volumeSlider;
    UIButton            *_playButton;
    UIButton            *_rewindButton;
    UIButton            *_forwardButton;
    UIButton            *_doneButton;
    UIButton            *_loopbackButton;
    UIButton            *_commentButton;
    UILabel             *_progressLabel;
    UILabel             *_leftLabel;
//    UIButton            *_infoButton;
    UIButton            *_scaleButton;
    UITableView         *_tableView;
    UIActivityIndicatorView *_activityIndicatorView;
    UILabel             *_subtitlesLabel;
    
    UITapGestureRecognizer *_tapGestureRecognizer;
//    UITapGestureRecognizer *_doubleTapGestureRecognizer;
    UIPanGestureRecognizer *_panGestureRecognizer;
    UIPinchGestureRecognizer *_pinchGestureRecognizer;
        
#ifdef DEBUG
    UILabel             *_messageLabel;
    NSTimeInterval      _debugStartTime;
    NSUInteger          _debugAudioStatus;
    NSDate              *_debugAudioStatusTS;
#endif

    CGFloat             _bufferedDuration;
    CGFloat             _minBufferedDuration;
    CGFloat             _maxBufferedDuration;
    BOOL                _buffered;
    
    BOOL                _savedIdleTimer;
    
    NSDictionary        *_parameters;
    NSTimer             *_seekTimer;
    BOOL                _showComment, _repeatVideo;
    BOOL                _shouldBeHidingStatusBar;
    BOOL                _backgroundMode;
    NSMutableDictionary *_nowPlayingInfo;
    CGFloat             _decodeDuration;
    CGFloat             _seekPosition;
    UILabel             *_scrubbingSpeedLabel;
    UILabel             *_scrubbingLabel;
    BOOL                _savedPlayMode, _isSeek;

    CGFloat             _lastDuration;
    NSTimeInterval      _lastPresentTime;

    NicoCommentManager *_nicoCommentManager;
}

@property (readwrite) BOOL playing;
@property (readwrite) BOOL decoding;
@property (readwrite, strong) KxArtworkFrame *artworkFrame;

- (CGFloat)syncAudio;
- (void)asyncDecodeFrames:(CGFloat)duration;

- (void)seekTimerFired:(NSTimer*)timer;
- (void)progressDidTouchDown:(id)sender;
- (void)progressDidTouchUp:(id)sender;

- (void)toggleShowComment:(BOOL)save;
- (void)toggleRepeatVideo:(BOOL)save;

- (void)screenSizeAndVideoSize;
- (UIImage*)createIconFromAwesomeFont:(NSString*)code size:(CGFloat)size color:(UIColor*)color imageSize:(CGSize)imageSize;
@end

@implementation KxMovieViewController

+ (void)initialize
{
    if (!gHistory)
        gHistory = [NSMutableDictionary dictionary];
}

+ (id) movieViewControllerWithContentPath: (NSString *) path
                               parameters: (NSDictionary *) parameters
{    
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    [audioManager activateAudioSession];    
    return [[KxMovieViewController alloc] initWithContentPath: path parameters: parameters];
}

- (id) initWithContentPath: (NSString *) path
                parameters: (NSDictionary *) parameters
{
    NSAssert(path.length > 0, @"empty path");
    
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        
        _moviePosition = 0;
//        self.wantsFullScreenLayout = YES;
                
        _parameters = parameters;

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _showComment = ![defaults boolForKey:@"PLAYER_COMMENT_DISABLED"];
        _repeatVideo = ![defaults boolForKey:@"PLAYER_REPEAT_DISABLED"];

        _shouldBeHidingStatusBar = YES;
        _backgroundMode = NO;
        _decodeDuration = 0.1f;
        _seekPosition = -1;
        _isSeek = NO;


        NSDictionary *videoInfo = [_parameters valueForKey:KxMovieParameterVideoInfo];
        if (videoInfo) {
          _nowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:@{
            MPMediaItemPropertyTitle: [videoInfo valueForKey:@"title"],
            MPMediaItemPropertyPlaybackDuration: @(0.0),
          }];

          UIImage *image = [UIImage imageWithData:[videoInfo valueForKey:@"thumbImage"]];
          if (image) {
            _nowPlayingInfo[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:image];
          }
        }
        

        __weak KxMovieViewController *weakSelf = self;
        
        KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
        decoder.backgroundMode = NO;
        
        decoder.interruptCallback = ^BOOL(){
            
            __strong KxMovieViewController *strongSelf = weakSelf;
            return strongSelf ? [strongSelf interruptDecoder] : YES;
        };
        
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
    
            NSError *error = nil;
            [decoder openFile:path error:&error];
                        
            __strong KxMovieViewController *strongSelf = weakSelf;
            if (strongSelf) {
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    
                    [strongSelf setMovieDecoder:decoder withError:error];                    
                });
            }
        });
    }
    return self;
}

- (void) dealloc
{
    [self pause];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_dispatchQueue) {
#if !OS_OBJECT_USE_OBJC
        dispatch_release(_dispatchQueue);
#endif
        _dispatchQueue = NULL;
    }
    
    NSLog(@"%@ dealloc", self);
}

- (void)loadView
{
    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    CGRect bounds = [[UIScreen mainScreen] applicationFrame];
    
    self.view = [[UIView alloc] initWithFrame:bounds];
    self.view.backgroundColor = [UIColor blackColor];
    
    _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleWhiteLarge];
    _activityIndicatorView.center = self.view.center;
    _activityIndicatorView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    
    [self.view addSubview:_activityIndicatorView];
    
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    CGFloat y = statusBarFrame.size.height;
    
#ifdef DEBUG
    _messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20,40,width-40,40)];
    _messageLabel.backgroundColor = [UIColor clearColor];
    _messageLabel.textColor = [UIColor redColor];
    _messageLabel.font = [UIFont systemFontOfSize:14];
    _messageLabel.numberOfLines = 2;
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_messageLabel];
#endif
    
//    _topHUD      = [[HudView alloc] initWithFrame:CGRectMake(0, statusBarFrame.size.height, width, 30.f)];
    _topHUD      = [[HudView alloc] initWithFrame:CGRectMake(0, 0, width, 30.f + y)];
    _bottomHUD   = [[UIView alloc] initWithFrame:CGRectMake(30, height - (75 + 15), width - (30 * 2), 75)];
    
    _topHUD.opaque = NO;
    _topHUD.backgroundColor = [UIColor colorWithWhite:.4f alpha:.6f];
    _topHUD.clipsToBounds = YES;
    _bottomHUD.opaque = NO;
    _bottomHUD.backgroundColor = [UIColor colorWithWhite:.4f alpha:.6f];
    
    _topHUD.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _bottomHUD.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin;
    
    [self.view addSubview:_topHUD];
    [self.view addSubview:_bottomHUD];
    
    // top hud
    
    _doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _doneButton.frame = CGRectMake(0, y + 4.f, 50.f, 24.f);
    _doneButton.backgroundColor = [UIColor clearColor];
    [_doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_doneButton setTitle:NSLocalizedString(@"Done", nil) forState:UIControlStateNormal];
    _doneButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    _doneButton.showsTouchWhenHighlighted = YES;
    [_doneButton addTarget:self action:@selector(doneDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(35.f, y + 5.f, 50.f, 20.f)];
    _progressLabel.backgroundColor = [UIColor clearColor];
    _progressLabel.opaque = NO;
    _progressLabel.adjustsFontSizeToFitWidth = NO;
    _progressLabel.textAlignment = NSTextAlignmentRight;
    _progressLabel.textColor = [UIColor whiteColor];
    _progressLabel.text = @"-";
    _progressLabel.font = [UIFont systemFontOfSize:12];
    
    _progressSlider = [[VideoSeekSlider alloc] initWithFrame:CGRectMake(90.f, y + 10.f + 4.f, width - 182.f, 20.f)];
    _progressSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
//    _progressSlider.continuous = NO;
    _progressSlider.continuous = YES;
    _progressSlider.value = 0;
    _progressSlider.delegate = self;

    
    _leftLabel = [[UILabel alloc] initWithFrame:CGRectMake(width - 87.f, y + 5.f, 60.f, 20.f)];
    _leftLabel.backgroundColor = [UIColor clearColor];
    _leftLabel.opaque = NO;
    _leftLabel.adjustsFontSizeToFitWidth = NO;
    _leftLabel.textAlignment = NSTextAlignmentLeft;
    _leftLabel.textColor = [UIColor whiteColor];
    _leftLabel.text = @"-";
    _leftLabel.font = [UIFont systemFontOfSize:12];
    _leftLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    
//    _infoButton = [UIButton buttonWithType:UIButtonTypeInfoDark];
//    _infoButton.frame = CGRectMake(width-25,5,20,20);
//    _infoButton.showsTouchWhenHighlighted = YES;
//    _infoButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
//    [_infoButton addTarget:self action:@selector(infoDidTouch:) forControlEvents:UIControlEventTouchUpInside];

    _scaleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _scaleButton.frame = CGRectMake(width - 35, y + 8, 14, 14);
    _scaleButton.showsTouchWhenHighlighted = YES;
    _scaleButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_scaleButton setImage:[UIImage imageNamed:@"11-arrows-out"] forState:UIControlStateNormal];
    [_scaleButton addTarget:self action:@selector(scaleDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    

    _scrubbingSpeedLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, y + 27.f, self.view.bounds.size.width, 20.f)];
    _scrubbingSpeedLabel.backgroundColor = [UIColor clearColor];
    _scrubbingSpeedLabel.opaque = NO;
    _scrubbingSpeedLabel.adjustsFontSizeToFitWidth = NO;
    _scrubbingSpeedLabel.textAlignment = NSTextAlignmentCenter;
    _scrubbingSpeedLabel.textColor = [UIColor whiteColor];
    _scrubbingSpeedLabel.text = [NSString stringWithFormat:@"100%@", NSLocalizedString(@"ScrubbingSpeed", nil)];
    _scrubbingSpeedLabel.font = [UIFont systemFontOfSize:12];
    _scrubbingSpeedLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth;

    _scrubbingLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, y + 43.f, self.view.bounds.size.width, 20.f)];
    _scrubbingLabel.backgroundColor = [UIColor clearColor];
    _scrubbingLabel.opaque = NO;
    _scrubbingLabel.adjustsFontSizeToFitWidth = NO;
    _scrubbingLabel.textAlignment = NSTextAlignmentCenter;
    _scrubbingLabel.textColor = [UIColor whiteColor];
    _scrubbingLabel.text = NSLocalizedString(@"ScrubbingMessage", nil);
    _scrubbingLabel.font = [UIFont systemFontOfSize:12];
    _scrubbingLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth;

    [_topHUD addSubview:_doneButton];
    [_topHUD addSubview:_progressLabel];
    [_topHUD addSubview:_progressSlider];
    [_topHUD addSubview:_leftLabel];
//    [_topHUD addSubview:_infoButton];
    [_topHUD addSubview:_scaleButton];
    [_topHUD addSubview:_scrubbingSpeedLabel];
    [_topHUD addSubview:_scrubbingLabel];
    
    // bottom hud
    
    width = _bottomHUD.bounds.size.width;
    
    _loopbackButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _loopbackButton.frame = CGRectMake(width * 0.5 - 115, 5, 40, 40);
    _loopbackButton.showsTouchWhenHighlighted = YES;
    [_loopbackButton addTarget:self action:@selector(repeatVideoDidTouch:) forControlEvents:UIControlEventTouchUpInside];

    _rewindButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _rewindButton.frame = CGRectMake(width * 0.5 - 65, 5, 40, 40);
    _rewindButton.backgroundColor = [UIColor clearColor];
    _rewindButton.showsTouchWhenHighlighted = YES;
    [_rewindButton setImage:[UIImage imageNamed:@"kxmovie.bundle/playback_rew"] forState:UIControlStateNormal];
    [_rewindButton addTarget:self action:@selector(rewindDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _playButton.frame = CGRectMake(width * 0.5 - 20, 5, 40, 40);
    _playButton.backgroundColor = [UIColor clearColor];
    _playButton.showsTouchWhenHighlighted = YES;
    [_playButton setImage:[UIImage imageNamed:@"kxmovie.bundle/playback_play"] forState:UIControlStateNormal];
    [_playButton addTarget:self action:@selector(playDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    _forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _forwardButton.frame = CGRectMake(width * 0.5 + 25, 5, 40, 40);
    _forwardButton.backgroundColor = [UIColor clearColor];
    _forwardButton.showsTouchWhenHighlighted = YES;
    [_forwardButton setImage:[UIImage imageNamed:@"kxmovie.bundle/playback_ff"] forState:UIControlStateNormal];
    [_forwardButton addTarget:self action:@selector(forwardDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    _commentButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _commentButton.frame = CGRectMake(width * 0.5 + 75, 5, 40, 40);
    _commentButton.showsTouchWhenHighlighted = YES;
    [_commentButton addTarget:self action:@selector(showCommentDidTouch:) forControlEvents:UIControlEventTouchUpInside];

    _volumeSlider = [[MPVolumeView alloc] initWithFrame:CGRectMake(5, 50, width-(5 * 2), 20)];
    _volumeSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
//    _volumeSlider.showsRouteButton = NO;
    _volumeSlider.showsRouteButton = YES;
    _volumeSlider.showsVolumeSlider = YES;
    
    [self toggleRepeatVideo:NO];
    [self toggleShowComment:NO];

    [_bottomHUD addSubview:_loopbackButton];
    [_bottomHUD addSubview:_rewindButton];
    [_bottomHUD addSubview:_playButton];
    [_bottomHUD addSubview:_forwardButton];
    [_bottomHUD addSubview:_commentButton];
    [_bottomHUD addSubview:_volumeSlider];
    
    // gradients
    
//    CAGradientLayer *gradient;
//    
//    gradient = [CAGradientLayer layer];
//    gradient.frame = _bottomHUD.bounds;
//    gradient.cornerRadius = 5;
//    gradient.masksToBounds = YES;
//    gradient.borderColor = [UIColor darkGrayColor].CGColor;
//    gradient.borderWidth = 1.0f;
//    gradient.colors = [NSArray arrayWithObjects:
//                       (id)[[UIColor whiteColor] colorWithAlphaComponent:0.4].CGColor,
//                       (id)[[UIColor lightGrayColor] colorWithAlphaComponent:0.4].CGColor,
//                       (id)[[UIColor darkGrayColor] colorWithAlphaComponent:0.4].CGColor,
//                       (id)[[UIColor blackColor] colorWithAlphaComponent:0.4].CGColor,
//                       nil];
//    gradient.locations = [NSArray arrayWithObjects:
//                          [NSNumber numberWithFloat:0.0f],
//                          [NSNumber numberWithFloat:0.1f],
//                          [NSNumber numberWithFloat:0.5],
//                          [NSNumber numberWithFloat:0.9],
//                          nil];
//    [_bottomHUD.layer insertSublayer:gradient atIndex:0];
    
    
//    gradient = [CAGradientLayer layer];
//    gradient.frame = _topHUD.bounds;
//    gradient.colors = [NSArray arrayWithObjects:
//                       (id)[[UIColor lightGrayColor] colorWithAlphaComponent:0.7].CGColor,
//                       (id)[[UIColor darkGrayColor] colorWithAlphaComponent:0.7].CGColor,
//                       nil];
//    gradient.locations = [NSArray arrayWithObjects:
//                          [NSNumber numberWithFloat:0.0f],
//                          [NSNumber numberWithFloat:0.5],
//                          nil];
//    [_topHUD.layer insertSublayer:gradient atIndex:0];
    
    if (_decoder) {
        
        [self setupPresentView];
        
    } else {
        
        _bottomHUD.hidden = YES;
        _progressLabel.hidden = YES;
        _progressSlider.hidden = YES;
        _leftLabel.hidden = YES;
//        _infoButton.hidden = YES;
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden {
    return _shouldBeHidingStatusBar;
}

- (NSUInteger)supportedInterfaceOrientations {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger playerOrientation = [defaults integerForKey:@"PLAYER_ORIENTATION"];

    if (playerOrientation) {
      return playerOrientation;
    }
    else {
      return UIInterfaceOrientationMaskAll;
    }
}

- (BOOL)shouldAutorotate {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger playerOrientation = [defaults integerForKey:@"PLAYER_ORIENTATION"];
    return (playerOrientation == 0);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self screenSizeAndVideoSize];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    if (self.playing) {
        
        [self pause];
        [self freeBufferedFrames];
        
        if (_maxBufferedDuration > 0) {
            
            _minBufferedDuration = _maxBufferedDuration = 0;
            [self play];
            
            NSLog(@"didReceiveMemoryWarning, disable buffering and continue playing");
            
        } else {
            
            // force ffmpeg to free allocated memory
            [_decoder closeFile];
//            [_decoder openFile:nil error:nil];
            
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                        message:NSLocalizedString(@"Out of memory", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                              otherButtonTitles:nil] show];
        }
        
    } else {
        
        [self freeBufferedFrames];
        [_decoder closeFile];
//        [_decoder openFile:nil error:nil];
    }
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self showHUD:YES];
}

- (void) viewDidAppear:(BOOL)animated
{
    // NSLog(@"viewDidAppear");
    
    [super viewDidAppear:animated];
        
    if (self.presentingViewController)
        [self fullscreenMode:YES];
    
    if (_infoMode)
        [self showInfoView:NO animated:NO];
    
    _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
    
//    [self showHUD: YES];
    
    if (_decoder) {
        
        [self restorePlay];
        
    } else {
        [_activityIndicatorView startAnimating];
    }
   
        
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:[UIApplication sharedApplication]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:[UIApplication sharedApplication]];


    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
}

- (void) viewWillDisappear:(BOOL)animated
{    
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self resignFirstResponder];
    
    [super viewWillDisappear:animated];
    
    [_activityIndicatorView stopAnimating];
    
    if (_decoder) {
        
        [self pause];
        
//        if (_moviePosition == 0 || _decoder.isEOF)
//            [gHistory removeObjectForKey:_decoder.path];
//        else if (!_decoder.isNetwork)
//            [gHistory setValue:[NSNumber numberWithFloat:_moviePosition]
//                        forKey:_decoder.path];
    }
    
    if (_fullscreen)
        [self fullscreenMode:NO];
        
//    [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];

    [_activityIndicatorView stopAnimating];
    _buffered = NO;
    _interrupted = YES;
    
    [_nicoCommentManager stop];

    [_seekTimer invalidate];
    _seekTimer = nil;
      
    NSLog(@"viewWillDisappear %@", self);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void) applicationWillResignActive: (NSNotification *)notification
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL playerBackgroundDisabled = [defaults boolForKey:@"PLAYER_BACKGROUND_DISABLED"];

    if (playerBackgroundDisabled) {
      [self showHUD:YES];
      [self pause];
    }

    NSLog(@"applicationWillResignActive");    
}

- (void) applicationDidEnterBackground: (NSNotification *)notification
{
    _backgroundMode = YES;
//    _decoder.backgroundMode = YES;

    if (_glView) {
      [_glView render:nil];
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL playerBackgroundDisabled = [defaults boolForKey:@"PLAYER_BACKGROUND_DISABLED"];
    if (!playerBackgroundDisabled) {
      if (_nowPlayingInfo) {
        _nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(_decoder.duration);
        _nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(_moviePosition - _decoder.startTime);
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = _nowPlayingInfo;
      }
    }
}

- (void) applicationWillEnterForeground: (NSNotification *)notification
{
    if (_backgroundMode) {
//      if (!_decoder.isEOF) {

      _backgroundMode = NO;
//      _decoder.backgroundMode = NO;
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - gesture recognizer

- (void) handleTap: (UITapGestureRecognizer *) sender
{
    if (sender.state == UIGestureRecognizerStateEnded) {
        
        if (sender == _tapGestureRecognizer) {

            [self showHUD: _hiddenHUD];
            
        } 
//        else if (sender == _doubleTapGestureRecognizer) {
//                
//            UIView *frameView = [self frameView];
//            
//            if (frameView.contentMode == UIViewContentModeScaleAspectFit)
//                frameView.contentMode = UIViewContentModeScaleAspectFill;
//            else
//                frameView.contentMode = UIViewContentModeScaleAspectFit;
//            
//        }        
    }
}

- (void) handlePan: (UIPanGestureRecognizer *) sender
{
    if (sender.state == UIGestureRecognizerStateEnded) {
        
        const CGPoint vt = [sender velocityInView:self.view];
        const CGPoint pt = [sender translationInView:self.view];
        const CGFloat sp = MAX(0.1, log10(fabsf(vt.x)) - 1.0);
        const CGFloat sc = fabsf(pt.x) * 0.33 * sp;
        if (sc > 10) {
            
            const CGFloat ff = pt.x > 0 ? 1.0 : -1.0;            
            [self setMoviePosition: _moviePosition + ff * MIN(sc, 600.0)];
        }
        //NSLog(@"pan %.2f %.2f %.2f sec", pt.x, vt.x, sc);
    }
}

- (void) handlePinch: (UIPinchGestureRecognizer *) sender
{
    UIView *frameView = [self frameView];
    NSString *imageName;

    if (frameView.contentMode == UIViewContentModeScaleAspectFit) {
      frameView.contentMode = UIViewContentModeScaleAspectFill;
      imageName = @"10-arrows-in";
    }
    else {
      frameView.contentMode = UIViewContentModeScaleAspectFit;
      imageName = @"11-arrows-out";
    }

    [_scaleButton setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
    [self screenSizeAndVideoSize];
}

#pragma mark - public

-(void) play
{
    if (self.playing)
        return;
    
    if (!_decoder.validVideo &&
        !_decoder.validAudio) {
        
        return;
    }
    
    if (_interrupted)
        return;

    self.playing = YES;
    _interrupted = NO;
    _disableUpdateHUD = NO;
    _tickCorrectionTime = 0;
    _tickCounter = 0;

#ifdef DEBUG
    _debugStartTime = -1;
#endif

    [self asyncDecodeFrames];
    [self updatePlayButton];

    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });

    if (_decoder.validAudio)
        [self enableAudio:YES];

    [_nicoCommentManager startCommentLayer];  

    NSLog(@"play movie");    
}

- (void) pause
{
    if (!self.playing)
        return;

    self.playing = NO;
    //_interrupted = YES;
    [self enableAudio:NO];
    [self updatePlayButton];

    [_nicoCommentManager stopCommentLayer];  


    NSLog(@"pause movie");
}

- (void) setMoviePosition: (CGFloat) position
{
    BOOL playMode = self.playing;
    
    self.playing = NO;
    _disableUpdateHUD = YES;
    [self enableAudio:NO];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

        [self updatePosition:position playMode:playMode];
    });
}

#pragma mark - actions

- (void) doneDidTouch: (id) sender
{
    if (self.presentingViewController || !self.navigationController)
        [self dismissViewControllerAnimated:YES completion:nil];
    else
        [self.navigationController popViewControllerAnimated:YES];
}

- (void) infoDidTouch: (id) sender
{
    [self showInfoView: !_infoMode animated:YES];
}

- (void) scaleDidTouch: (id) sender
{
    [self handlePinch: nil];
}

- (void) playDidTouch: (id) sender
{
    if (self.playing) {
        [self pause];
    }
    else {
        [self play];
    }
}

- (void) forwardDidTouch: (id) sender
{
    [self setMoviePosition: _moviePosition + 10];
}

- (void) rewindDidTouch: (id) sender
{
    [self setMoviePosition: _moviePosition - 10];
}

- (void) progressDidChange: (id) sender
{
    NSAssert(_decoder.duration != MAXFLOAT, @"bugcheck");

    UISlider *slider = sender;
    CGFloat position = slider.value * _decoder.duration;
    CGFloat delta = _seekPosition - position;

    [self updateHUD];

    if ((delta <= 1 && delta > 0) || (delta >= -1 && delta < 0)) return;
    _seekPosition = position;

    if (_seekTimer) {
      [_seekTimer invalidate];
      _seekTimer = nil;
    }

    _seekTimer = [NSTimer 
      scheduledTimerWithTimeInterval:0.1f 
                              target:self 
                            selector:@selector(seekTimerFired:)
                            userInfo:nil 
                             repeats:NO];
}

- (void)seekTimerFired:(NSTimer*)timer {
    CGFloat position = _progressSlider.value * _decoder.duration;

    if (!_isSeek && floor(_seekPosition) == floor(position)) {
      _isSeek = YES;
      _decoder.interruptSeek = YES;
      [self setMoviePosition:_seekPosition];
    }
}

- (void)progressDidTouchDown:(id)sender {
    _savedPlayMode = self.playing;

    self.playing = NO;
    [self enableAudio:NO];
    [_nicoCommentManager stopCommentLayer];  


    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    CGFloat height = MIN(statusBarFrame.size.height, statusBarFrame.size.width);

    [UIView animateWithDuration:0.3f
                          delay:0.f
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                       CGRect frame = _topHUD.frame;
                       frame.size.height = height + 65.f;
                       _topHUD.frame = frame;
                     }
                     completion:^(BOOL finished){
                     }];
}

- (void)progressDidTouchUp:(id)sender {
    if (_seekTimer) {
      [_seekTimer invalidate];
      _seekTimer = nil;
    }

//    CGFloat position = _progressSlider.value * _decoder.duration;
    self.playing = _savedPlayMode;
    [self setMoviePosition:_seekPosition];


    CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
    CGFloat height = MIN(statusBarFrame.size.height, statusBarFrame.size.width);

    [UIView animateWithDuration:0.3f
                          delay:0.f
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                       CGRect frame = _topHUD.frame;
                       frame.size.height = height + 30.f;
                       _topHUD.frame = frame;
                     }
                     completion:^(BOOL finished){
                     }];
}

#pragma mark - private

- (void) setMovieDecoder: (KxMovieDecoder *) decoder
               withError: (NSError *) error
{
    NSLog(@"setMovieDecoder");
            
    if (!error && decoder) {
        
        _decoder        = decoder;
        _dispatchQueue  = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL);

        _videoFrames    = [NSMutableArray array];
        _audioFrames    = [NSMutableArray array];
        
        if (_decoder.subtitleStreamsCount) {
            _subtitles = [NSMutableArray array];
        }
    
        if (_decoder.isNetwork) {
            
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
            
        } else {
            
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
        
        if (!_decoder.validVideo)
            _minBufferedDuration *= 10.0; // increase for audio
                
        // allow to tweak some parameters at runtime
        if (_parameters.count) {
            
            id val;
            
            val = [_parameters valueForKey: KxMovieParameterMinBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _minBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterMaxBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _maxBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterDisableDeinterlacing];
            if ([val isKindOfClass:[NSNumber class]])
                _decoder.disableDeinterlacing = [val boolValue];

            val = [_parameters valueForKey: KxMovieParameterDecodeDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _decodeDuration = [val floatValue];
            
            if (_maxBufferedDuration < _minBufferedDuration)
                _maxBufferedDuration = _minBufferedDuration * 2;
        }
        
        NSLog(@"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        
        if (self.isViewLoaded) {
            
            [self setupPresentView];
            
            _bottomHUD.hidden       = NO;
            _progressLabel.hidden   = NO;
            _progressSlider.hidden  = NO;
            _leftLabel.hidden       = NO;
//            _infoButton.hidden      = NO;
            
            if (_activityIndicatorView.isAnimating) {
                
                [_activityIndicatorView stopAnimating];
                // if (self.view.window)
                [self restorePlay];
            }
        }
        
    } else {
        
         if (self.isViewLoaded && self.view.window) {
        
             [_activityIndicatorView stopAnimating];
             if (!_interrupted)
                 [self handleDecoderMovieError: error];
         }
    }
}

- (void) restorePlay
{
    NSNumber *n = [gHistory valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];

//    dispatch_async(dispatch_get_main_queue(), ^{
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      [self screenSizeAndVideoSize];
      [_nicoCommentManager start];
//    });
}

- (void) setupPresentView
{
    CGRect bounds = self.view.bounds;
    
    if (_decoder.validVideo) {
        _glView = [[KxMovieGLView alloc] initWithFrame:bounds decoder:_decoder];
    } 
    
    if (!_glView) {
        
        NSLog(@"fallback to use RGB video frame and UIKit");
        [_decoder setupVideoFrameFormat:KxVideoFrameFormatRGB];
        _imageView = [[UIImageView alloc] initWithFrame:bounds];
    }
    
    UIView *frameView = [self frameView];
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.view insertSubview:frameView atIndex:0];
        
    if (_decoder.validVideo) {
    
        [self setupUserInteraction];
    
    } else {
       
        _imageView.image = [UIImage imageNamed:@"kxmovie.bundle/music_icon.png"];
        _imageView.contentMode = UIViewContentModeCenter;
    }
    
    self.view.backgroundColor = [UIColor clearColor];
    
    if (_decoder.duration == MAXFLOAT) {
        
        _leftLabel.text = @"\u221E"; // infinity
        _leftLabel.font = [UIFont systemFontOfSize:14];
        
        CGRect frame;
        
        frame = _leftLabel.frame;
        frame.origin.x += 40;
        frame.size.width -= 40;
        _leftLabel.frame = frame;
        
        frame =_progressSlider.frame;
        frame.size.width += 40;
        _progressSlider.frame = frame;
        
    } else {
        
        [_progressSlider addTarget:self
                            action:@selector(progressDidChange:)
                  forControlEvents:UIControlEventValueChanged];
        [_progressSlider addTarget:self
                            action:@selector(progressDidTouchDown:)
                  forControlEvents:UIControlEventTouchDown];
        [_progressSlider addTarget:self
                            action:@selector(progressDidTouchUp:)
                  forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside)];
    }
    
    if (_decoder.subtitleStreamsCount) {
        
        CGSize size = self.view.bounds.size;
        
        _subtitlesLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, size.height, size.width, 0)];
        _subtitlesLabel.numberOfLines = 0;
        _subtitlesLabel.backgroundColor = [UIColor clearColor];
        _subtitlesLabel.opaque = NO;
        _subtitlesLabel.adjustsFontSizeToFitWidth = NO;
        _subtitlesLabel.textAlignment = NSTextAlignmentCenter;
        _subtitlesLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _subtitlesLabel.textColor = [UIColor whiteColor];
        _subtitlesLabel.font = [UIFont systemFontOfSize:16];
        _subtitlesLabel.hidden = YES;

        [self.view addSubview:_subtitlesLabel];
    }


    _nicoCommentManager = [NicoCommentManager nicoCommentManagerWithComments:self.videoComment delegate:self];
}

- (void) setupUserInteraction
{
    UIView * view = [self frameView];
    view.userInteractionEnabled = YES;
    
    _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _tapGestureRecognizer.numberOfTapsRequired = 1;
    
//    _doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
//    _doubleTapGestureRecognizer.numberOfTapsRequired = 2;
    
//    [_tapGestureRecognizer requireGestureRecognizerToFail: _doubleTapGestureRecognizer];
    
//    [view addGestureRecognizer:_doubleTapGestureRecognizer];
    [view addGestureRecognizer:_tapGestureRecognizer];
    
//    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
//    _panGestureRecognizer.enabled = NO;
//    
//    [view addGestureRecognizer:_panGestureRecognizer];


//    _pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
//    [view addGestureRecognizer:_pinchGestureRecognizer];
}

- (UIView *) frameView
{
    return _glView ? _glView : _imageView;
}

- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    //fillSignalF(outData,numFrames,numChannels);
    //return;

    if (_buffered) {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }

    @autoreleasepool {
        
        while (numFrames > 0) {
            
            if (!_currentAudioFrame) {
                
                @synchronized(_audioFrames) {
                    
                    NSUInteger count = _audioFrames.count;
                    
                    if (count > 0) {
                        
                        KxAudioFrame *frame = _audioFrames[0];
                        
                        if (_decoder.validVideo) {
                        
                            const CGFloat delta = _moviePosition - frame.position;
                            
                            if (delta < -2.0) {
                                memset(outData, 0, numFrames * numChannels * sizeof(float));
#ifdef DEBUG
                                NSLog(@"desync audio (outrun) wait %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 1;
                                _debugAudioStatusTS = [NSDate date];
#endif
                                break; // silence and exit
                            }
                            
                            [_audioFrames removeObjectAtIndex:0];
                            
                            if (delta > 2.0 && count > 1) {
                                
#ifdef DEBUG
                                NSLog(@"desync audio (lags) skip %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 2;
                                _debugAudioStatusTS = [NSDate date];
#endif
                                continue;
                            }
                            
                        } else {
                            
                            [_audioFrames removeObjectAtIndex:0];
                            _moviePosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;                        
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;                
                
            } else {
                
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                //NSLog(@"silence audio");
#ifdef DEBUG
                _debugAudioStatus = 3;
                _debugAudioStatusTS = [NSDate date];
#endif
                break;
            }
        }
    }
}

- (void) enableAudio: (BOOL) on
{
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
            
    if (on && _decoder.validAudio) {
                
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
            [self audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
        
        NSLog(@"audio device smr: %d fmt: %d chn: %d",
              (int)audioManager.samplingRate,
              (int)audioManager.numBytesPerSample,
              (int)audioManager.numOutputChannels);
        
    } else {
        
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}

- (BOOL) addFrames: (NSArray *)frames
{
    if (_decoder.validVideo) {
        
        @synchronized(_videoFrames) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
        }
    }
    
    if (_decoder.validAudio) {
        
        @synchronized(_audioFrames) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (!_decoder.validVideo)
                        _bufferedDuration += frame.duration;
                }
        }
        
        if (!_decoder.validVideo) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeArtwork)
                    self.artworkFrame = (KxArtworkFrame *)frame;
        }
    }
    
    if (_decoder.validSubtitles) {
        
        @synchronized(_subtitles) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeSubtitle) {
                    [_subtitles addObject:frame];
                }
        }
    }
    
    return self.playing && _bufferedDuration < _maxBufferedDuration;
}

- (BOOL) decodeFrames
{
    //NSAssert(dispatch_get_current_queue() == _dispatchQueue, @"bugcheck");
    
    NSArray *frames = nil;
    
    if (_decoder.validVideo ||
        _decoder.validAudio) {
        
        frames = [_decoder decodeFrames:0];
    }
    
    if (frames.count) {
        return [self addFrames: frames];
    }
    return NO;
}

- (void) asyncDecodeFrames {
    const CGFloat duration = _decoder.isNetwork ? .0f : _decodeDuration;

    [self asyncDecodeFrames:duration];
}

- (void) asyncDecodeFrames:(CGFloat)duration 
{
    if (self.decoding)
        return;
    
    __weak KxMovieViewController *weakSelf = self;
    __weak KxMovieDecoder *weakDecoder = _decoder;
    
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        
        {
            __strong KxMovieViewController *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
        }
        
        BOOL good = YES;
        while (good) {
            
            good = NO;
            
            @autoreleasepool {
                
                __strong KxMovieDecoder *decoder = weakDecoder;
                
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    
                    NSArray *frames = [decoder decodeFrames:duration];
                    if (frames.count) {
                        
                        __strong KxMovieViewController *strongSelf = weakSelf;
                        if (strongSelf)
                            good = [strongSelf addFrames:frames];
                    }
                }
            }
        }
                
        {
            __strong KxMovieViewController *strongSelf = weakSelf;
            if (strongSelf) strongSelf.decoding = NO;
        }
    });
}

- (void) tick
{
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        
        _tickCorrectionTime = 0;
        _buffered = NO;
        [_activityIndicatorView stopAnimating];        
        [_nicoCommentManager startCommentLayer];  
    }
    
    CGFloat interval = 0;
    if (!_buffered)
        interval = [self presentFrame];
    
    if (self.playing) {
        
        const NSUInteger leftFrames =
        (_decoder.validVideo ? _videoFrames.count : 0) +
        (_decoder.validAudio ? _audioFrames.count : 0);
        
        if (0 == leftFrames) {
            
            if (_decoder.isEOF) {
                if (_repeatVideo) {
                  [self setMoviePosition:0.f];
                }
                else {
                  [self pause];
                  [self updateHUD];
                }
                return;
            }
            
            if (_minBufferedDuration > 0 && !_buffered) {
                                
                _buffered = YES;
                [_activityIndicatorView startAnimating];
                [_nicoCommentManager stopCommentLayer];  
            }
        }
        
        if (!leftFrames ||
            !(_bufferedDuration > _minBufferedDuration)) {
            
            [self asyncDecodeFrames];
        }
        

        if (_audioFrames.count > 0 && _videoFrames.count > 0) {
          CGFloat duration = [self syncAudio];
          if (duration > 0.f) {
            [self asyncDecodeFrames:duration];
          }
        }

        const NSTimeInterval correction = [self tickCorrection];
        const NSTimeInterval time = MAX(interval + correction, 0.01);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self tick];
        });
    }

    if ((_tickCounter++ % 3) == 0) {
        [self updateHUD];
    }
}

- (CGFloat)syncAudio {
    if (_buffered) return 0.f;

    KxAudioFrame *audioFrame;
    CGFloat delta;
    @synchronized(_audioFrames) {
      audioFrame = _audioFrames[0];
      delta = _moviePosition - audioFrame.position;
    }
    CGFloat duration = 0.f;
    NSMutableArray *removeObjects = [NSMutableArray array];

    if (delta < -1.f) {
      delta = fabs(delta);
      @synchronized(_videoFrames) {
        for (KxVideoFrame *videoFrame in _videoFrames) {
          duration += videoFrame.duration;
          _bufferedDuration -= videoFrame.duration;
          [removeObjects addObject:videoFrame];

          if (duration >= delta) break;
        }

        [_videoFrames removeObjectsInArray:removeObjects];
      }
    }
    else if (delta > 1.f) {
      delta = fabs(delta);
      @synchronized(_audioFrames) {
        for (KxAudioFrame *audioFrame in _audioFrames) {
          duration += audioFrame.duration;
          [removeObjects addObject:audioFrame];

          if (duration >= delta) break;
        }

        [_audioFrames removeObjectsInArray:removeObjects];
      }
    }

    return duration;
}

- (CGFloat) tickCorrection
{
    if (_buffered)
        return 0;
    
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime) {
        
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    //if ((_tickCounter % 200) == 0)
    //    NSLog(@"tick correction %.4f", correction);
    
    if (correction > 1.f || correction < -1.f) {
        
        NSLog(@"tick correction reset %.2f", correction);
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

- (CGFloat) presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        
        KxVideoFrame *frame;
        
        @synchronized(_videoFrames) {
            
            if (_videoFrames.count > 0) {
                

                if (floor(_lastDuration + _moviePosition) < floor(((KxVideoFrame*)_videoFrames[0]).position)) {
                  const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

                  _moviePosition += (now - _lastPresentTime);
                  _lastPresentTime = [NSDate timeIntervalSinceReferenceDate];
                }
                else {
                  frame = _videoFrames[0];
                  [_videoFrames removeObjectAtIndex:0];
                  _bufferedDuration -= frame.duration;
                }

            }
        }

        if (frame) {
          _lastPresentTime = [NSDate timeIntervalSinceReferenceDate];

          if (_backgroundMode) {
            _moviePosition = frame.position;
            interval = frame.duration;
          }
          else {
            interval = [self presentVideoFrame:frame];
          }
          _lastDuration = interval;
        }
        
    } else if (_decoder.validAudio) {

        //interval = _bufferedDuration * 0.5;
                
        if (self.artworkFrame) {
            
            _imageView.image = [self.artworkFrame asImage];
            self.artworkFrame = nil;
        }
    }

    if (_decoder.validSubtitles)
        [self presentSubtitles];
    
#ifdef DEBUG
    if (self.playing && _debugStartTime < 0)
        _debugStartTime = [NSDate timeIntervalSinceReferenceDate] - _moviePosition;
#endif

    return interval;
}

- (CGFloat) presentVideoFrame: (KxVideoFrame *) frame
{
    if (_glView) {
        
        [_glView render:frame];
        
    } else {
        
        KxVideoFrameRGB *rgbFrame = (KxVideoFrameRGB *)frame;
        _imageView.image = [rgbFrame asImage];
    }
    
    _moviePosition = frame.position;
        
    return frame.duration;
}

- (void) presentSubtitles
{
    NSArray *actual, *outdated;
    
    if ([self subtitleForPosition:_moviePosition
                           actual:&actual
                         outdated:&outdated]){
        
        if (outdated.count) {
            @synchronized(_subtitles) {
                [_subtitles removeObjectsInArray:outdated];
            }
        }
        
        if (actual.count) {
            
            NSMutableString *ms = [NSMutableString string];
            for (KxSubtitleFrame *subtitle in actual.reverseObjectEnumerator) {
                if (ms.length) [ms appendString:@"\n"];
                [ms appendString:subtitle.text];
            }
            
            if (![_subtitlesLabel.text isEqualToString:ms]) {
                
                CGSize viewSize = self.view.bounds.size;

                NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
                style.lineBreakMode = NSLineBreakByTruncatingTail;
                CGSize size = [ms boundingRectWithSize:CGSizeMake(viewSize.width, viewSize.height * 0.5)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{ NSFontAttributeName:_subtitlesLabel.font,
                                             NSParagraphStyleAttributeName: style
                                          }
                                  context:nil].size;

                _subtitlesLabel.text = ms;
                _subtitlesLabel.frame = CGRectMake(0, viewSize.height - size.height - 10,
                                                   viewSize.width, size.height);
                _subtitlesLabel.hidden = NO;
            }
            
        } else {
            
            _subtitlesLabel.text = nil;
            _subtitlesLabel.hidden = YES;
        }
    }
}

- (BOOL) subtitleForPosition: (CGFloat) position
                      actual: (NSArray **) pActual
                    outdated: (NSArray **) pOutdated
{
    if (!_subtitles.count)
        return NO;
    
    NSMutableArray *actual = nil;
    NSMutableArray *outdated = nil;
    
    for (KxSubtitleFrame *subtitle in _subtitles) {
        
        if (position < subtitle.position) {
            
            break; // assume what subtitles sorted by position
            
        } else if (position >= (subtitle.position + subtitle.duration)) {
            
            if (pOutdated) {
                if (!outdated)
                    outdated = [NSMutableArray array];
                [outdated addObject:subtitle];
            }
            
        } else {
            
            if (pActual) {
                if (!actual)
                    actual = [NSMutableArray array];
                [actual addObject:subtitle];
            }
        }
    }
    
    if (pActual) *pActual = actual;
    if (pOutdated) *pOutdated = outdated;
    
    return actual.count || outdated.count;
}

- (void) updatePlayButton
{
    [_playButton setImage:[UIImage imageNamed:self.playing ? @"kxmovie.bundle/playback_pause" : @"kxmovie.bundle/playback_play"]
                 forState:UIControlStateNormal];
}

- (void) updateHUD
{
    if (_disableUpdateHUD)
        return;
    
    const CGFloat duration = _decoder.duration;
    const CGFloat position = _moviePosition -_decoder.startTime;
    
    if (_progressSlider.state == UIControlStateNormal) {
      if (!_progressSlider.tracking) {
        _progressSlider.value = position / duration;
      }

      if (_decoder.isNetwork) {
        CGFloat preloadValue = [_decoder.videoCacheManager preloadProgressValue];
        [_progressSlider setPreloadValue:preloadValue animated:YES];
      }
    }
    _progressLabel.text = formatTimeInterval(position, NO);
    
    if (_decoder.duration != MAXFLOAT)
        _leftLabel.text = formatTimeInterval(duration - position, YES);



#ifdef DEBUG
    const NSTimeInterval timeSinceStart = [NSDate timeIntervalSinceReferenceDate] - _debugStartTime;
    NSString *subinfo = _decoder.validSubtitles ? [NSString stringWithFormat: @" %lu",(unsigned long)_subtitles.count] : @"";
    
    NSString *audioStatus;
    
    if (_debugAudioStatus) {
        
        if (NSOrderedAscending == [_debugAudioStatusTS compare: [NSDate dateWithTimeIntervalSinceNow:-0.5]]) {
            _debugAudioStatus = 0;
        }
    }
    
    if (_debugAudioStatus == 1) audioStatus = @"\n(audio outrun)";
    else if (_debugAudioStatus == 2) audioStatus = @"\n(audio lags)";
    else if (_debugAudioStatus == 3) audioStatus = @"\n(audio silence)";
    else audioStatus = @"";
    
    _messageLabel.text = [NSString stringWithFormat:@"%lu %lu%@ %c - %@ %@ %@\n%@",
                          (unsigned long)_videoFrames.count,
                          (unsigned long)_audioFrames.count,
                          subinfo,
                          self.decoding ? 'D' : ' ',
                          formatTimeInterval(timeSinceStart, NO),
                          //timeSinceStart > _moviePosition + 0.5 ? @" (lags)" : @"",
                          _decoder.isEOF ? @"- END" : @"",
                          audioStatus,
                          _buffered ? [NSString stringWithFormat:@"buffering %.1f%%", _bufferedDuration / _minBufferedDuration * 100] : @""];
#endif
}

- (void) showHUD: (BOOL) show
{
    _hiddenHUD = !show;    
//    _panGestureRecognizer.enabled = _hiddenHUD;
        
    [[UIApplication sharedApplication] setIdleTimerDisabled:_hiddenHUD];
    

    _shouldBeHidingStatusBar = _hiddenHUD;

    [UIView animateWithDuration:0.2
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                     animations:^{
                         [self setNeedsStatusBarAppearanceUpdate];
                         
                         CGFloat alpha = _hiddenHUD ? 0 : 1;
                         _topHUD.alpha = alpha;
                         _bottomHUD.alpha = alpha;
                     }
                     completion:^(BOOL finished) {
                     }];
    
}

- (void) fullscreenMode: (BOOL) on
{
    _fullscreen = on;
    UIApplication *app = [UIApplication sharedApplication];
    [app setStatusBarHidden:on withAnimation:UIStatusBarAnimationNone];
    // if (!self.presentingViewController) {
    //[self.navigationController setNavigationBarHidden:on animated:YES];
    //[self.tabBarController setTabBarHidden:on animated:YES];
    // }
}

- (void) setMoviePositionFromDecoder
{
    _moviePosition = _decoder.position;
}

- (void) setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
    _lastDuration = 0.f;
}

- (void) enableUpdateHUD
{
    _disableUpdateHUD = NO;
}

- (void) updatePosition: (CGFloat) position
               playMode: (BOOL) playMode
{
    [self freeBufferedFrames];
    
    position = MIN(_decoder.duration - 1, MAX(0, position));
    
    __weak KxMovieViewController *weakSelf = self;

    dispatch_async(_dispatchQueue, ^{
        
        if (playMode) {
        
            {
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
        
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf play];

                    if (_showComment) {
                      [_nicoCommentManager seekCommentLayer:!playMode];  
                    }
                }

                _isSeek = NO;
            });
            
        } else {

            {
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
                [strongSelf decodeFrames];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (strongSelf) {
                
                    [strongSelf enableUpdateHUD];
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                    [strongSelf updateHUD];

                    if (_showComment) {
                      [_nicoCommentManager seekCommentLayer:!playMode];  
                    }

                    _isSeek = NO;
                }
            });
        }        
    });
}

- (void) freeBufferedFrames
{
    @synchronized(_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized(_audioFrames) {
        
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
    
    if (_subtitles) {
        @synchronized(_subtitles) {
            [_subtitles removeAllObjects];
        }
    }
    
    _bufferedDuration = 0;
}

- (void) showInfoView: (BOOL) showInfo animated: (BOOL)animated
{
/*
    if (!_tableView)
        [self createTableView];

    [self pause];
    
    CGSize size = self.view.bounds.size;
    CGFloat Y = _topHUD.bounds.size.height;
    
    if (showInfo) {
        
        _tableView.hidden = NO;
        
        if (animated) {
        
            [UIView animateWithDuration:0.4
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                             animations:^{
                                 
                                 _tableView.frame = CGRectMake(0,Y,size.width,size.height - Y);
                             }
                             completion:nil];
        } else {
            
            _tableView.frame = CGRectMake(0,Y,size.width,size.height - Y);
        }
    
    } else {
        
        if (animated) {
            
            [UIView animateWithDuration:0.4
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                             animations:^{
                                 
                                 _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
                                 
                             }
                             completion:^(BOOL f){
                                 
                                 if (f) {
                                     _tableView.hidden = YES;
                                 }
                             }];
        } else {
        
            _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
            _tableView.hidden = YES;
        }
    }
    
    _infoMode = showInfo;    
*/
}

- (void) createTableView
{    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.hidden = YES;
    
    CGSize size = self.view.bounds.size;
    CGFloat Y = _topHUD.bounds.size.height;
    _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
    
    [self.view addSubview:_tableView];   
}

- (void) handleDecoderMovieError: (NSError *) error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];
}

- (BOOL) interruptDecoder
{
    //if (!_decoder)
    //    return NO;
    return _interrupted;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return KxMovieInfoSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case KxMovieInfoSectionGeneral:
            return NSLocalizedString(@"General", nil);
        case KxMovieInfoSectionMetadata:
            return NSLocalizedString(@"Metadata", nil);
        case KxMovieInfoSectionVideo: {
            NSArray *a = _decoder.info[@"video"];
            return a.count ? NSLocalizedString(@"Video", nil) : nil;
        }
        case KxMovieInfoSectionAudio: {
            NSArray *a = _decoder.info[@"audio"];
            return a.count ?  NSLocalizedString(@"Audio", nil) : nil;
        }
        case KxMovieInfoSectionSubtitles: {
            NSArray *a = _decoder.info[@"subtitles"];
            return a.count ? NSLocalizedString(@"Subtitles", nil) : nil;
        }
    }
    return @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case KxMovieInfoSectionGeneral:
            return KxMovieInfoGeneralCount;
            
        case KxMovieInfoSectionMetadata: {
            NSDictionary *d = [_decoder.info valueForKey:@"metadata"];
            return d.count;
        }
            
        case KxMovieInfoSectionVideo: {
            NSArray *a = _decoder.info[@"video"];
            return a.count;
        }
            
        case KxMovieInfoSectionAudio: {
            NSArray *a = _decoder.info[@"audio"];
            return a.count;
        }
            
        case KxMovieInfoSectionSubtitles: {
            NSArray *a = _decoder.info[@"subtitles"];
            return a.count ? a.count + 1 : 0;
        }
            
        default:
            return 0;
    }
}

- (id) mkCell: (NSString *) cellIdentifier
    withStyle: (UITableViewCellStyle) style
{
    UITableViewCell *cell = [_tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:cellIdentifier];
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    
    if (indexPath.section == KxMovieInfoSectionGeneral) {
    
        if (indexPath.row == KxMovieInfoGeneralBitrate) {
            
            int bitrate = [_decoder.info[@"bitrate"] intValue];
            cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
            cell.textLabel.text = NSLocalizedString(@"Bitrate", nil);
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d kb/s",bitrate / 1000];
            
        } else if (indexPath.row == KxMovieInfoGeneralFormat) {

            NSString *format = _decoder.info[@"format"];
            cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
            cell.textLabel.text = NSLocalizedString(@"Format", nil);
            cell.detailTextLabel.text = format ? format : @"-";
        }
        
    } else if (indexPath.section == KxMovieInfoSectionMetadata) {
      
        NSDictionary *d = _decoder.info[@"metadata"];
        NSString *key = d.allKeys[indexPath.row];
        cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = key.capitalizedString;
        cell.detailTextLabel.text = [d valueForKey:key];
        
    } else if (indexPath.section == KxMovieInfoSectionVideo) {
        
        NSArray *a = _decoder.info[@"video"];
        cell = [self mkCell:@"VideoCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = a[indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 2;
        
    } else if (indexPath.section == KxMovieInfoSectionAudio) {
        
        NSArray *a = _decoder.info[@"audio"];
        cell = [self mkCell:@"AudioCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = a[indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 2;
        BOOL selected = _decoder.selectedAudioStream == indexPath.row;
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        
    } else if (indexPath.section == KxMovieInfoSectionSubtitles) {
        
        NSArray *a = _decoder.info[@"subtitles"];
        
        cell = [self mkCell:@"SubtitleCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 1;
        
        if (indexPath.row) {
            cell.textLabel.text = a[indexPath.row - 1];
        } else {
            cell.textLabel.text = NSLocalizedString(@"Disable", nil);
        }
        
        const BOOL selected = _decoder.selectedSubtitleStream == (indexPath.row - 1);
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    
     cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == KxMovieInfoSectionAudio) {
        
        NSInteger selected = _decoder.selectedAudioStream;
        
        if (selected != indexPath.row) {

            _decoder.selectedAudioStream = indexPath.row;
            NSInteger now = _decoder.selectedAudioStream;
            
            if (now == indexPath.row) {
            
                UITableViewCell *cell;
                
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
                
                indexPath = [NSIndexPath indexPathForRow:selected inSection:KxMovieInfoSectionAudio];
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
        }
        
    } else if (indexPath.section == KxMovieInfoSectionSubtitles) {
        
        NSInteger selected = _decoder.selectedSubtitleStream;
        
        if (selected != (indexPath.row - 1)) {
            
            _decoder.selectedSubtitleStream = indexPath.row - 1;
            NSInteger now = _decoder.selectedSubtitleStream;
            
            if (now == (indexPath.row - 1)) {
                
                UITableViewCell *cell;
                
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
                
                indexPath = [NSIndexPath indexPathForRow:selected + 1 inSection:KxMovieInfoSectionSubtitles];
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
            
            // clear subtitles
            _subtitlesLabel.text = nil;
            _subtitlesLabel.hidden = YES;
            @synchronized(_subtitles) {
                [_subtitles removeAllObjects];
            }
        }
    }
}

- (void)toggleShowComment:(BOOL)save {
    if (save) {
      _showComment = !_showComment;

      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      BOOL playerCommentSave = [defaults boolForKey:@"PLAYER_COMMENT_SAVE"];
      if (playerCommentSave) {
        [defaults setBool:@(!_showComment) forKey:@"PLAYER_COMMENT_DISABLED"];
      }
    }

    UIImage *image;
    if (_showComment) {
      image = [self createIconFromAwesomeFont:@"\uf075" size:20.f color:[UIColor whiteColor] imageSize:CGSizeMake(20.f, 20.f)];
    }
    else {
      image = [self createIconFromAwesomeFont:@"\uf075" size:20.f color:[UIColor colorWithWhite:.1f alpha:.6f] imageSize:CGSizeMake(20.f, 20.f)];
    }

    [_commentButton setImage:image forState:UIControlStateNormal];
}

- (void)toggleRepeatVideo:(BOOL)save {
    if (save) {
      _repeatVideo = !_repeatVideo;

      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      BOOL playerRepeatSave = [defaults boolForKey:@"PLAYER_REPEAT_SAVE"];
      if (playerRepeatSave) {
        [defaults setBool:@(!_repeatVideo) forKey:@"PLAYER_REPEAT_DISABLED"];
      }
    }

    UIImage *image;
    if (_repeatVideo) {
      image = [self createIconFromAwesomeFont:@"\uf01e" size:20.f color:[UIColor whiteColor] imageSize:CGSizeMake(20.f, 20.f)];
    }
    else {
      image = [self createIconFromAwesomeFont:@"\uf01e" size:20.f color:[UIColor colorWithWhite:.1f alpha:.6f] imageSize:CGSizeMake(20.f, 20.f)];
    }

    [_loopbackButton setImage:image forState:UIControlStateNormal];
}

- (void)showCommentDidTouch:(id)sender {
    [self toggleShowComment:YES];

    if (_showComment) {
      [_nicoCommentManager seekCommentLayer:!self.playing];
    }
    else {
      [_nicoCommentManager deleteAllCommentLayer];  
    }
}

- (void)repeatVideoDidTouch:(id)sender {
    [self toggleRepeatVideo:YES];
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type == UIEventTypeRemoteControl) {
      switch (event.subtype) {
      case UIEventSubtypeRemoteControlPlay:
        LOG(@"UIEventSubtypeRemoteControlPlay");
        [self play];
        break;
      case UIEventSubtypeRemoteControlPause:
        LOG(@"UIEventSubtypeRemoteControlPause");
        [self pause];
        break;
      case UIEventSubtypeRemoteControlStop:
        LOG(@"UIEventSubtypeRemoteControlStop");
        [self pause];
        break;
      case UIEventSubtypeRemoteControlTogglePlayPause:
        LOG(@"UIEventSubtypeRemoteControlTogglePlayPause");
        [self playDidTouch:nil];
        break;
      case UIEventSubtypeRemoteControlNextTrack:
        break;
      case UIEventSubtypeRemoteControlPreviousTrack:
        break;
      case UIEventSubtypeRemoteControlBeginSeekingBackward:
        break;
      case UIEventSubtypeRemoteControlEndSeekingBackward:
        break;
      case UIEventSubtypeRemoteControlBeginSeekingForward:
        break;
      case UIEventSubtypeRemoteControlEndSeekingForward:
        break;
      default:
        break;
      }
    }
}

- (void)slider:(CPSlider *)slider didChangeToSpeed:(CGFloat)speed whileTracking:(BOOL)tracking {
    _scrubbingSpeedLabel.text = [NSString stringWithFormat:@"%ld%@", 
      (NSInteger)(speed * 100),
      NSLocalizedString(@"ScrubbingSpeed", nil)];
}


- (void)screenSizeAndVideoSize {
    UIView *frameView = [self frameView];
    CGSize videoSize = CGSizeMake(_decoder.frameWidth, _decoder.frameHeight);
    CGFloat videoScale = self.view.bounds.size.width / videoSize.width;
    CGSize screenSize;

    if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation)) {
      screenSize = self.view.bounds.size;
    }
    else {
      if (frameView.contentMode == UIViewContentModeScaleAspectFit) {
        screenSize = CGSizeMake(self.view.bounds.size.width, floor(videoSize.height * videoScale));
      }
      else {
        screenSize = self.view.bounds.size;
      }
    }

    [_nicoCommentManager setupPresentView:frameView 
                                videoSize:videoSize 
                               screenSize:screenSize 
                              isLandscape:UIInterfaceOrientationIsLandscape(self.interfaceOrientation)];
}

- (CGFloat)willShowComments:(BOOL)seek {
    if (!self.playing || !_showComment || _buffered) {
      if (_showComment && seek) return _moviePosition;

      return -1;
    }

    return _moviePosition;
}


- (UIImage*)createIconFromAwesomeFont:(NSString*)code size:(CGFloat)size color:(UIColor*)color imageSize:(CGSize)imageSize {
    FAKFontAwesome *font = [FAKFontAwesome iconWithCode:code size:size];
    [font addAttribute:NSForegroundColorAttributeName value:color];
    return [font imageWithSize:imageSize];
}
@end
