//
//  VideoCacheManager.m
//  SmilePlayer2
//
//  Created by Pontago on 2014/01/12.
//
//

#import "VideoCacheManager.h"

NSInteger const BUFFER_SIZE           = 32768;
NSTimeInterval const PRELOAD_TIMEOUT  = 600.f;
NSTimeInterval const READ_TIMEOUT     = 3.f;

NSString* const HTTP_USERAGENT        = @"Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_6_3; ja-jp) AppleWebKit/533.16 (KHTML, like Gecko) Version/5.0 Safari/533.16";

static int network_read(void *h, uint8_t* buf, int size) {
    VideoCacheManager *videoCacheManager = (__bridge VideoCacheManager*)h;

    int len = -1;
    int readedBytes = 0;

    @autoreleasepool {
      NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
      NSTimeInterval currentTime;

      while (readedBytes < size) {
        if (videoCacheManager.stop) break;

        len = [videoCacheManager readVideo:buf size:(size - readedBytes)];
        if (len > 0) {
          readedBytes += len;
          break;
        }
        else {
          currentTime = [[NSDate date] timeIntervalSince1970];
          if ((currentTime - startTime) > READ_TIMEOUT) break;
          sleep(1);
        }
      }
    }

    return readedBytes;
}

static int64_t network_seek(void *h, int64_t pos, int whence) {
    VideoCacheManager *videoCacheManager = (__bridge VideoCacheManager*)h;

    if (videoCacheManager.stop) return -1;

    return [videoCacheManager seekVideo:pos whence:whence];
}

@interface VideoCacheManager () {
    int64_t _position;
    int64_t _offset;
    NSInteger _totalBytesRead;

    NSFileHandle *_outputFileHandle;
    NSURLConnection *_urlConnection;
    NSURLResponse *_urlResponse;
    NSString *_url;
}

- (void)_createTempFile;
- (void)_createConnection:(int64_t)offset;
- (void)_deleteConnection;
- (int64_t)_seek:(int64_t)offset;
@end

@implementation VideoCacheManager
- (id)init {
    self = [super init];
    if (self) {
      _position = 0;
      _offset = 0;
      _totalBytesRead = 0;
      _stop = NO;
    }
    return self;
}

- (void)dealloc {
    LOG(@"dealloc VideoCacheManager");
    [self close];
}

- (BOOL)open:(NSString*)url {
    [self _createTempFile];

    int buffer_size = BUFFER_SIZE;
    uint8_t *buffer = av_malloc(buffer_size);
    _ioContext = avio_alloc_context(buffer, buffer_size, 0, (__bridge void *)(self), 
      network_read, NULL, network_seek);
    if (_ioContext) {
      _ioContext->max_packet_size = BUFFER_SIZE;
      _url = url;
      [self _createConnection:-1];
    }
    else {
      return NO;
    }

    return YES;
}

- (void)close {
    _stop = YES;

    if (_urlConnection) {
      [self _deleteConnection];
    }

    if (_ioContext) {
      _ioContext->opaque = NULL;
      av_freep(&_ioContext->buffer);
      av_free(_ioContext);

      _ioContext = NULL;
    }

    if (_outputFileHandle) {
      [_outputFileHandle closeFile];
      _outputFileHandle = nil;
    }
}

- (void)_createTempFile {
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"test"];

    [fileManager removeItemAtPath:path error:nil];
    [fileManager createFileAtPath:path contents:[NSData data] attributes:nil];
    _outputFileHandle = [NSFileHandle fileHandleForUpdatingAtPath:path];
}

- (void)_createConnection:(int64_t)offset {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_url]
                                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                                         timeoutInterval:PRELOAD_TIMEOUT];
      [request setValue:HTTP_USERAGENT forHTTPHeaderField:@"User-Agent"];

      if (offset > 0) {
        NSString *requestRange = [NSString stringWithFormat:@"bytes=%llu-", offset];
        [request setValue:requestRange forHTTPHeaderField:@"Range"];
      }

      _urlConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
      [_urlConnection start];
    });
}

- (void)_deleteConnection {
    [_urlConnection cancel];
    _urlConnection = nil;
}

- (int64_t)_seek:(int64_t)offset {
    if (offset == 13) return -1;

    [self _deleteConnection];

    [_outputFileHandle truncateFileAtOffset:0];
    _offset = 0;
    _position = offset;
    _totalBytesRead = 0;

    [self _createConnection:_position];

    return offset;
}


- (int)readVideo:(uint8_t*)buf size:(int)size {
    int len = 0;

    @synchronized(_outputFileHandle) {
      uint64_t length = _totalBytesRead;

      if (length > (_offset + size)) {
        len = size;
      }
      else {
        len = (int)(length - _offset);
      }

      [_outputFileHandle seekToFileOffset:_offset];
      NSData *data = [_outputFileHandle readDataOfLength:len];
      [data getBytes:buf length:len];

      _offset += len;
    }

    return len;
}

- (int64_t)seekVideo:(int64_t)offset whence:(int)whence {
    int64_t seek = -1;

    if (whence == SEEK_SET) {
//      @synchronized(_outputFileHandle) {
        int64_t totalBytes = _urlResponse.expectedContentLength + _position;
        uint64_t length = _totalBytesRead;

//        if ((totalBytes - 55) > offset) {
        if ((totalBytes - 59) > offset) {
          int64_t downloadedOffset = length + _position;

          if (offset >= _position && offset <= downloadedOffset) {
            _offset = offset - _position;
            seek = offset;
          }
          else {
LOG(@"b - %lld", offset);
            seek = [self _seek:offset];
          }
        }
//      }
    }
    else if (whence == AVSEEK_SIZE) {
      seek = _urlResponse.expectedContentLength + _position;
    }

    return seek;
}

- (CGFloat)preloadProgressValue {
    CGFloat progress = 0.f;

    int64_t totalBytes = _urlResponse.expectedContentLength + _position;
    uint64_t length = _totalBytesRead;
    progress = (CGFloat)(_position + length) / totalBytes;

    return progress;
}



- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    LOG(@"didReceiveResponse");
    _urlResponse = response;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    NSUInteger length = [data length];

    @synchronized(_outputFileHandle) {
      [_outputFileHandle seekToEndOfFile];
      [_outputFileHandle writeData:data];
    }

    _totalBytesRead += length;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LOG(@"connectionDidFinishLoading");
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    LOG(@"didFailWithError");
}
@end
