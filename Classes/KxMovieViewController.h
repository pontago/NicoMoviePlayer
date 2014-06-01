//
//  ViewController.h
//  kxmovieapp
//
//  Created by Kolyvan on 11.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import <UIKit/UIKit.h>
#import "VideoSeekSlider.h"
#import "NicoCommentManager.h"

@class KxMovieDecoder;

extern NSString * const KxMovieParameterMinBufferedDuration;    // Float
extern NSString * const KxMovieParameterMaxBufferedDuration;    // Float
extern NSString * const KxMovieParameterDisableDeinterlacing;   // BOOL

extern NSString * const KxMovieParameterVideoInfo;
extern NSString * const KxMovieParameterDecodeDuration;

@interface KxMovieViewController : UIViewController<UITableViewDataSource, UITableViewDelegate, CPSliderDelegate, NicoCommentManagerDelegate>

+ (id) movieViewControllerWithContentPath: (NSString *) path
                               parameters: (NSDictionary *) parameters;

@property (readonly) BOOL playing;
@property (readwrite, nonatomic, strong) NSArray *videoComment;

- (void) play;
- (void) pause;

@end
