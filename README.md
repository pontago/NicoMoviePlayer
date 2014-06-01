NicoMoviePlayer - A movie player for iOS based on kxmovie.
==========================================================

### Build Instructions

First you need to download, configure and build [FFmpeg](http://ffmpeg.org/index.html). For this, open console and type in:
	
	cd FFmpegBuild
	rake

### Build Instructions

NicoMoviePlayer is available through CocoaPods, to install it simply add the following line to your Podfile:

	pod 'CPSlider'
	pod 'FontAwesomeKit'

### Usage

	KxMovieViewController *movieViewController = [KxMovieViewController movieViewControllerWithContentPath:path parameters:nil];
	movieViewController.videoComment = @[
	  @{
	       @"vpos": @(0),
	       @"body": @"NicoNico",
	        @"position": @(COMMENT_POSITION_NORMAL),
	        @"fontSize": @(COMMENT_SIZE_NORMAL),
	        @"color": @(0xffffff),
	    }
	  ];
	[self presentViewController:movieViewController animated:YES completion:NULL];

### Requirements

At least iOS 7.0 and iPhone 4 (because of iOS 7 requirements).

## Credits

This project uses the following 3rd party libraries:

- kxmovie
- CPSlider
- FontAwesomeKit
