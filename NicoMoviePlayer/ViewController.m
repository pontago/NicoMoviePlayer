//
//  ViewController.m
//  NicoMoviePlayer
//
//  Created by pontago on 2014/05/27.
//
//

#import "ViewController.h"
#import "KxMovieViewController.h"
#import "NicoCommentUtil.h"

@interface ViewController ()
- (NSArray*)_createVideoComment;
- (NSString*)_createNicoMail;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)playVideo:(id)sender {
    NSString *videoUrl = @"http://www.gomplayer.jp/img/sample/mp4_h264_aac.mp4";
    KxMovieViewController *movieViewController = 
     [KxMovieViewController movieViewControllerWithContentPath:videoUrl
                                                    parameters:nil];
    movieViewController.videoComment = [self _createVideoComment];
    [self presentViewController:movieViewController animated:YES completion:NULL];
}

- (NSArray*)_createVideoComment {
    NicoCommentUtil *nicoCommentUtil = [[NicoCommentUtil alloc] init];
    NSInteger videoDuration = 2000;
    NSInteger commentNum = 50;
    NSMutableArray *videoComments = [NSMutableArray array];

    for (NSInteger i = 0; i < commentNum; i++) {
      NSInteger vpos = arc4random_uniform((unsigned int)videoDuration);
      NSString *mail = [self _createNicoMail];

      NSDictionary *commentInfo = @{
        @"vpos": @(vpos),
        @"body": @"ニコニコ",
        @"position": @([nicoCommentUtil commentPosition:mail]),
        @"fontSize": @([nicoCommentUtil commentSize:mail]),
        @"color": [nicoCommentUtil commentColor:mail],
      };
      [videoComments addObject:commentInfo];
    }

    return [videoComments sortedArrayUsingComparator:^NSComparisonResult(
      NSDictionary *item1, NSDictionary *item2) {
        NSInteger vpos1 = [item1[@"vpos"] intValue];
        NSInteger vpos2 = [item2[@"vpos"] intValue];
        return vpos1 > vpos2;
    }];
}

- (NSString*)_createNicoMail {
    NSArray *commentPosition = @[
      @"ue",
      @"shita",
      @"",
    ];

    NSArray *commentFont = @[
      @"big",
      @"small",
      @"",
    ];

    NSArray *commentColor = @[
      @"red",
      @"pink",
      @"orange",
      @"yellow",
      @"green",
      @"cyan",
      @"blue",
      @"purple",
      @"black",
      @"niconicowhite",
      @"white2",
      @"truered",
      @"red2",
      @"passionorange",
      @"orange2",
      @"madyellow",
      @"yellow2",
      @"elementalgreen",
      @"green2",
      @"marinblue",
      @"blue2",
      @"nobleviolet",
      @"purple2",
      @"",
    ];

    NSMutableArray *strings = [NSMutableArray array];
    [strings addObject:commentPosition[arc4random_uniform((unsigned int)[commentPosition count])]];
    [strings addObject:commentFont[arc4random_uniform((unsigned int)[commentFont count])]];
    [strings addObject:commentColor[arc4random_uniform((unsigned int)[commentColor count])]];

    return [strings componentsJoinedByString:@" "];
}
@end
