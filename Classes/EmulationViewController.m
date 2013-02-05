    //
//  EmulationViewController.m
//  SNES4iPad
//
//  Created by Yusef Napora on 5/14/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "SNES4iOSAppDelegate.h"
#import "EmulationViewController.h"
#import "ScreenView.h"
#import "SNESControllerViewController.h"
#import "ScreenLayer.h"

#import <pthread.h>
#import <QuartzCore/QuartzCore.h>

#import "GPUImage.h"
#import "GPUImageFilterScanlines.h"
#import "GPUImageCRTFilter.h"

#import <AssetsLibrary/AssetsLibrary.h>

#define kSavedState @"savedState"

#define RADIANS(degrees) ((degrees * M_PI) / 180.0)
#define DEGREES(radians) (radians * 180.0/M_PI)


volatile int __emulation_run;
volatile int __emulation_saving;
volatile int __emulation_paused;

extern int iphone_main(char *filename);


pthread_t main_tid;


// C wrapper function for emulation core access
void refreshScreenSurface()
{
	//[AppDelegate().emulationViewController performSelectorOnMainThread:@selector(refreshScreen) withObject:nil waitUntilDone:NO];
    [AppDelegate().emulationViewController refreshScreen];
}

// entry point for emulator thread
void *threadedStart(NSString *completeFilePath)
{
	@autoreleasepool {
        void *romName = (void *)[[completeFilePath lastPathComponent] UTF8String];
        void *completeUTF8StringFilePath = (void*)[completeFilePath UTF8String];
		char *filename = malloc(strlen((char *)completeUTF8StringFilePath) + 1);
    strcpy(filename, (char *)romName);
		printf("Starting emulator for %s\n", filename);
		__emulation_run = 1;
		iphone_main(filename);
		__emulation_run = 0;
		__emulation_saving = 0;
		
    free(filename);
	}
}



extern unsigned short *vrambuffer;  // this holds the 256x224 framebuffer in L565 format

void convertBufferToARGB(unsigned int *dest, unsigned short *source, int w, int h)
{
    int x, y;
    // convert to ARGB
    for (y=0; y < h; y++) {
        for (x=0; x < w; x++) {
            unsigned int index = (y*w)+x;
            unsigned short source_pixel = source[index];  
            unsigned char r = (source_pixel & 0xf800) >> 11;
            unsigned char g = (source_pixel & 0x07c0) >> 5;
            unsigned char b = (source_pixel & 0x003f);
            dest[index] = 0xff000000 | 
                                      (((r << 3) | (r >> 2)) << 16) | 
                                      (((g << 2) | (g >> 4)) << 8)  | 
                                      ((b << 3) | (b >> 2));
        }
    }
    
}

// helper function to save a snapshot of the current framebuffer contents
void saveScreenshotToFile(char *filepath)
{
    NSLog(@"writing screenshot to %s", filepath);
    int width = 256;
    int height = 224;
    
    unsigned int *argb_buffer = (unsigned int *)malloc(width * height * 4);
    convertBufferToARGB(argb_buffer, vrambuffer, width, height);
    
    // make data provider from buffer
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, argb_buffer, (width * height * 4), NULL);

    // set up for CGImage creation
    int bitsPerComponent = 8;
    int bitsPerPixel = 32;
    int bytesPerRow = 4 * width;
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little |  kCGImageAlphaNoneSkipFirst;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    CGImageRef imageRef = CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow, colorSpaceRef, bitmapInfo, provider, NULL, NO, renderingIntent);

    UIImage *uiImage = [[UIImage alloc] initWithCGImage:imageRef];
	
	NSData *pngData = UIImagePNGRepresentation(uiImage);
	[pngData writeToFile:[NSString stringWithCString:filepath encoding:NSUTF8StringEncoding] atomically:YES];
	
	CGImageRelease(imageRef);
    free(argb_buffer);

}

@implementation EmulationViewController {
    GPUImageView *v;
    GPUImageRawDataInput *dataInput;
    GPUImageFilter *filter;
    
    NSArray *filtersArray;
    NSArray *filterData;
    
    int filterIndx;
    
    
    BOOL updating;
    GPUImageMovieWriter *mw;

    GLuint videoTexture;
    
    CFAbsoluteTime timeDiff;
}

@synthesize pauseAlert;
/*
 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        // Custom initialization
    }
    return self;
}
*/

-(NSURL *)movieURL {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *urlString = [tmpDir stringByAppendingPathComponent:@"movies/tmpMov.mov"];
    return [NSURL fileURLWithPath:urlString];
}

-(void)checkForAndDeleteFile {
    NSLog(@"checkfor and delete file");
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL exist = [fm fileExistsAtPath:[self movieURL].absoluteString];
    NSError *err;
    if (exist) {
        [fm removeItemAtURL:[self movieURL] error:&err];
        NSLog(@"file deleted");
        if (err) {
            NSLog(@"file remove error, %@", err.localizedDescription );
        }
        
    } else {
        NSLog(@"no file by that name");
    }
}

- (void)saveMovieToCameraRoll
{
    
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL exist = [fm fileExistsAtPath:[self movieURL].absoluteString];
    NSLog(@"save movie to camera roll, %d, %@", exist, [self movieURL].absoluteString);
	ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
	[library writeVideoAtPathToSavedPhotosAlbum:[self movieURL]
								completionBlock:^(NSURL *assetURL, NSError *error) {
									if (error) {
                                        NSLog(@"Error %@", [error localizedDescription]);
                                    } else {
                                        
                                        NSLog(@"finished saving");
                                    }
								}];
}


-(void)startRecordingVideo {
    [self checkForAndDeleteFile];
    mw = [[GPUImageMovieWriter alloc] initWithMovieURL:[self movieURL] size:CGSizeMake(480, 320)];
    timeDiff = CFAbsoluteTimeGetCurrent();
    [mw startRecording];
    [filter addTarget:mw];
    self.isRecording = YES;
}

-(void)finishRecordingVideo {
    [filter removeTarget:mw];
    [mw finishRecording];
    
    self.isRecording = NO;
    [self saveMovieToCameraRoll];
}

- (void)loadView {
	self.view = (UIView *)[[ScreenView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    updating = YES;
    v = [[GPUImageView alloc] initWithFrame:CGRectMake(0, 0, 480, 320)];
    [self.view addSubview:v];
    //self.view = v;
    /*
    if (ControllerAppDelegate().controllerType == SNESControllerTypeLocal) {
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didRotate:) name:@"UIDeviceOrientationDidChangeNotification" object:nil];
    }*/
    
    /*if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        UIButton *exitButton = [UIButton buttonWithType:UIButtonTypeCustom];
        exitButton.frame = CGRectMake(0, 0, 100, 100);
        [exitButton addTarget:self action:@selector(exit:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:exitButton];
        
        UIButton *loadStateButton = [UIButton buttonWithType:UIButtonTypeCustom];
        loadStateButton.frame = CGRectMake(self.view.bounds.size.width - 100, 0, 100, 100);
        [loadStateButton addTarget:self action:@selector(loadState:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:loadStateButton];
        
        UIButton *saveNewStateButton = [UIButton buttonWithType:UIButtonTypeCustom];
        saveNewStateButton.frame = CGRectMake(0, self.view.bounds.size.height - 100, 100, 100);
        saveNewStateButton.tag = 1;
        [saveNewStateButton addTarget:self action:@selector(saveState:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:saveNewStateButton];
        
        UIButton *saveStateButton = [UIButton buttonWithType:UIButtonTypeCustom];
        saveStateButton.frame = CGRectMake(self.view.bounds.size.width - 100, self.view.bounds.size.height - 100, 100, 100);
        saveStateButton.tag = 2;
        [saveStateButton addTarget:self action:@selector(saveState:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:saveStateButton];
    }*/
    //Above methods were a replacement to the double-tapping to access these options, which sometimes crashes the app. Convering over to GCD appears to have fixed this crash, but I've left these here just in case.
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"ChangeFilter" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        NSDictionary *inf = [note userInfo];
        if ([inf objectForKey:@"filterNumber"]) {
            [self setFilter:[[inf objectForKey:@"filterNumber"] intValue]];
        } else {
            [self rotateFilter];
        }
    }];
    
    NSMutableArray *ma = [NSMutableArray array];
    
    NSString *p = [[NSBundle mainBundle] pathForResource:@"Filters" ofType:@"plist"];
    filterData = [[NSArray arrayWithContentsOfFile:p] retain];
    
    /*
    for (NSDictionary *filterD in filterData) {
        NSString *className = [filterD objectForKey:@"FilterName"];
        Class clss = NSClassFromString(className);
        id f = [[clss alloc] init];
        
        NSLog(@"insert, %@, %@, %@", className, clss, f);
        [ma addObject:f];
    }
    */
    
    GPUImagePolarPixellateFilter *polarPixellate = [[GPUImagePolarPixellateFilter alloc] init];
    polarPixellate.pixelSize = CGSizeMake(0.1, 0.01);
    polarPixellate.center = CGPointMake(0.0, 0.0);
    GPUImageCannyEdgeDetectionFilter *canny = [[GPUImageCannyEdgeDetectionFilter alloc] init];
    GPUImagePixellateFilter *pixellate = [[GPUImagePixellateFilter alloc] init];
    pixellate.fractionalWidthOfAPixel = 0.02;
    GPUImageGaussianBlurFilter *blur = [[GPUImageGaussianBlurFilter alloc] init];
    GPUImageHalftoneFilter *halftone = [[GPUImageHalftoneFilter alloc] init];
    halftone.fractionalWidthOfAPixel = 0.03;
    GPUImageCrosshatchFilter *crosshatch = [[GPUImageCrosshatchFilter alloc] init];
    crosshatch.crossHatchSpacing = 0.03;
    GPUImageSmoothToonFilter *toon = [[GPUImageSmoothToonFilter alloc] init];
    GPUImageBulgeDistortionFilter *bulge = [[GPUImageBulgeDistortionFilter alloc] init];
    bulge.radius = .5;
    GPUImageUnsharpMaskFilter *unsharp = [[GPUImageUnsharpMaskFilter alloc] init];
    unsharp.intensity = 3;
    GPUImageSketchFilter *sketch = [[GPUImageSketchFilter alloc] init];
    GPUImageHueFilter *passThrough = [[GPUImageHueFilter alloc] init];
    passThrough.hue = 0;
    GPUImageFilterScanlines *scan = [[GPUImageFilterScanlines alloc] init];
    GPUImageCRTFilter *crt = [[GPUImageCRTFilter alloc] init];
    crt.CRTInputSize = CGPointMake(256, 224);
    crt.CRTOutputSize = CGPointMake(480, 320);
    GPUImageGlassSphereFilter *sphere = [[GPUImageGlassSphereFilter alloc] init];
    sphere.radius = .6;
    
    filtersArray = @[
    passThrough,
    sphere,
    scan,
    polarPixellate,
    canny,
    pixellate,
    blur,
    halftone,
    crosshatch,
    toon,
    bulge,
    unsharp,
    sketch
    ];
    
    [filtersArray retain];
    
    filter = filtersArray[0];
    
    [filter addTarget:v];
    
    /*
    //glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, videoTexture);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 256, 224, 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, vrambuffer);
    
    dataInput = [[GPUImageTextureInput alloc] initWithTexture:videoTexture size:CGSizeMake(256, 224)];
    //glActiveTexture(GL_TEXTURE);
     */
    dataInput = [[GPUImageRawDataInput alloc] initWithBytes:vrambuffer size:CGSizeMake(256, 224) pixelFormat:kDataInputPixelFormat_RGB565];
    
    [dataInput addTarget:filter];
    
    filterIndx = 0;
    
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(rotateFilter)];
    swipe.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:swipe];
}

/*
- (void)viewWillAppear:(BOOL)animated {
    [self didRotate:[NSNotification notificationWithName:@"RotateNotification" object:nil]];
}*/

#pragma mark - Save States

- (void)saveState:(id)sender {
    UIButton *button = (UIButton *)sender;
    __emulation_saving = button.tag;
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        NSString *message = @"Saved state!";
        if (button.tag == 1) {
            message = @"Saved new state!";
        }
    });
}

- (void)loadState:(id)sender {
    
}

#pragma mark -

- (void)exit:(id)sender {
    __emulation_run = 0;
    [AppDelegate() showEmulator:NO];
}

- (void) refreshScreen
{
    
    if (updating) {
     
        [dataInput updateDataFromBytes:vrambuffer size:CGSizeMake(256, 224) pixelFormat:kDataInputPixelFormat_RGB565];
        
        CMTime frameTime = CMTimeMakeWithSeconds(CFAbsoluteTimeGetCurrent() - timeDiff, 30);
        [dataInput processDataWithFrameTime:frameTime];
    }
    /*
    //glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, videoTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 256, 224, 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, vrambuffer);
    CMTime frameTime = CMTimeMakeWithSeconds(CFAbsoluteTimeGetCurrent(), 1000);
    [dataInput processTextureWithFrameTime:frameTime];
    */
}

- (void) startWithRom:(NSString *)romFile
{
    
    /*
    pthread_create(&main_tid, NULL, threadedStart, (void *) [[romFile lastPathComponent] UTF8String]);
	
	struct sched_param    param;
    param.sched_priority = 46;
    if(pthread_setschedparam(main_tid, SCHED_OTHER, &param) != 0)
    {
		fprintf(stderr, "Error setting pthread priority\n");
    }*/
    
    dispatch_queue_t dispatchQueue = dispatch_queue_create("EmulationThread", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(dispatchQueue, ^{
        NSLog(@"RomFile Path:%@", romFile);
        threadedStart(romFile);
    });
    dispatch_release(dispatchQueue);
}

- (BOOL) shouldAutorotate
{
    return NO;
}

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscapeRight & UIInterfaceOrientationMaskLandscapeLeft;
}

/*
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        return (interfaceOrientation == UIInterfaceOrientationLandscapeLeft ||
                interfaceOrientation == UIInterfaceOrientationLandscapeRight);
    }
    else {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
}*/

- (void) didRotate:(NSNotification *)notification {
    /*
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    if ((orientation == UIDeviceOrientationPortrait || orientation == UIDeviceOrientationLandscapeLeft || 
        orientation == UIDeviceOrientationLandscapeRight) && ![(UIAlertView *)self.pauseAlert isVisible] && self.view.superview != nil && [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        CGFloat rotationAngle = 0.0f;
        CGPoint anchorPoint = CGPointMake(0.0, 0.0);
        //These coordinates take into considerationt the fact that the UIWindow is in portrait mode
        if (orientation == UIDeviceOrientationPortrait) {
            if (![AppDelegate().snesControllerViewController.imageName isEqualToString:@"portrait_controller"]) {
                [AppDelegate().snesControllerViewController changeBackgroundImage:@"portrait_controller"];
                AppDelegate().snesControllerViewController.imageView.frame = CGRectMake(0, 240, 320, 240);
                AppDelegate().snesControllerViewController.imageView.alpha = 1.0f;
            }
            [UIApplication sharedApplication].statusBarOrientation = UIInterfaceOrientationPortrait;
            rotationAngle = 0.0f;
            self.view.superview.transform = CGAffineTransformRotate(CGAffineTransformIdentity, RADIANS(rotationAngle));
            self.view.transform = CGAffineTransformRotate(CGAffineTransformIdentity, RADIANS(0.0));
            self.view.bounds = CGRectMake(0, 0, 320, 240);
            ScreenLayer *layer = (ScreenLayer *)self.view.layer;
            layer.anchorPoint = anchorPoint;
            layer.rotateTransform = CGAffineTransformRotate(CGAffineTransformIdentity, RADIANS(0.0));
            self.view.superview.bounds = CGRectMake(0, 0, 320, 480);
            self.view.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
            self.view.superview.frame = CGRectMake(0, 0, self.view.superview.frame.size.width, self.view.superview.frame.size.height);
            
            AppDelegate().snesControllerViewController.sustainButton.center = CGPointMake(301, 461);
        }
        else if (orientation == UIDeviceOrientationLandscapeLeft) {
            if (![AppDelegate().snesControllerViewController.imageName isEqualToString:@"landscape_controller"]) {
                if ([AppDelegate().snesControllerViewController.imageName isEqualToString:@"portrait_controller"]) {
                    AppDelegate().snesControllerViewController.imageView.frame = CGRectMake(0, 0, 320, 480);
                }
                [AppDelegate().snesControllerViewController changeBackgroundImage:@"landscape_controller"];
                AppDelegate().snesControllerViewController.imageView.alpha = 0.5;
            }
            [UIApplication sharedApplication].statusBarOrientation = UIInterfaceOrientationLandscapeRight;
            //UIDeviceOrientationLandscapeLeft and UIInterfaceOrientationLandscapeLeft are NOT the same
            
            rotationAngle = 0.0f;
            self.view.superview.transform = CGAffineTransformIdentity;
            self.view.bounds = CGRectMake(0, 0, 480, 320);
            ScreenLayer *layer = (ScreenLayer *)self.view.layer;
            layer.anchorPoint = anchorPoint;
            layer.rotateTransform = CGAffineTransformRotate(CGAffineTransformIdentity, RADIANS(0.0));
            self.view.superview.bounds = CGRectMake(0, 0, 320, 480);
            //self.view.frame = CGRectMake(320, 0, self.view.frame.size.width, self.view.frame.size.height);
            self.view.superview.frame = CGRectMake(0, 0, self.view.superview.frame.size.width, self.view.superview.frame.size.height);
            
            AppDelegate().snesControllerViewController.sustainButton.center = CGPointMake(24, 456);
        }
        else if (orientation == UIDeviceOrientationLandscapeRight) {
            if (![AppDelegate().snesControllerViewController.imageName isEqualToString:@"landscape_controller"]) {
                if ([AppDelegate().snesControllerViewController.imageName isEqualToString:@"portrait_controller"]) {
                    AppDelegate().snesControllerViewController.imageView.frame = CGRectMake(0, 0, 320, 480);
                }
                [AppDelegate().snesControllerViewController changeBackgroundImage:@"landscape_controller"];
                AppDelegate().snesControllerViewController.imageView.alpha = 0.5;
            }
            [UIApplication sharedApplication].statusBarOrientation = UIInterfaceOrientationLandscapeLeft;
            rotationAngle = 180.0f;
            self.view.superview.transform = CGAffineTransformIdentity;
            self.view.superview.transform = CGAffineTransformRotate(CGAffineTransformIdentity, RADIANS(rotationAngle));
            self.view.bounds = CGRectMake(160, 0, 480, 320);
            ScreenLayer *layer = (ScreenLayer *)self.view.layer;
            layer.anchorPoint = anchorPoint;
            layer.rotateTransform = CGAffineTransformRotate(CGAffineTransformIdentity, RADIANS(0.0));
            self.view.superview.bounds = CGRectMake(0, 0, 320, 480);
            //self.view.frame = CGRectMake(320, 0, self.view.frame.size.width, self.view.frame.size.height);
            self.view.superview.frame = CGRectMake(0, 0, self.view.superview.frame.size.width, self.view.superview.frame.size.height);
            
            AppDelegate().snesControllerViewController.sustainButton.center = CGPointMake(24, 456);
        }
    }
     */
}

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	UITouch *touch = [touches anyObject];
	if (touch.tapCount == 2) {
        CGPoint touchPoint = [(UITouch *)touch locationInView:self.view];
        CGRect rect = CGRectMake(touchPoint.x, touchPoint.y, 60, 60);
		[self showPauseDialogFromRect:rect];
	}

}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:v];
    CGPoint prevLocation = [touch previousLocationInView:v];
    
    float adjustment = location.y - prevLocation.y;

}

-(void)setFilter:(int)filterNum {
    if (filterNum > 0 && filterNum < [filtersArray count]) {
        [dataInput removeTarget:filter];
        [filter removeTarget:v];
        filterIndx = filterNum;
        filter = [filtersArray objectAtIndex:filterIndx];
        [dataInput addTarget:filter];
        [filter addTarget:v];
        NSLog(@"New Filter %@", filter);
    }
}

-(void)rotateFilter {
    [dataInput removeTarget:filter];
    [filter removeTarget:v];
    filterIndx++;
    if (filterIndx > ([filtersArray count] - 1)) {
        filterIndx = 0;
    }
    filter = filtersArray[filterIndx];
    [dataInput addTarget:filter];
    [filter addTarget:v];
    NSLog(@"New Filter %@", filter);
}

- (void) showPauseDialogFromRect:(CGRect)rect {
    NSString *title = @"Select an option";
    NSString *destructiveButtonTitle = @"Quit Game";
    NSString *button1Title = @"Save State";
    NSString *button2Title = @"Save State to New File";
    NSString *newFilter = @"Rotate Filter";
    NSString *recording;
    if (self.isRecording) {
        recording = @"Stop Recording";
    } else {
        recording = @"Start Recording";
    }
    
    __emulation_paused = 1;
    //clearFramebuffer();
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        self.pauseAlert = (id)[[UIActionSheet alloc] initWithTitle:title
                                                           delegate:self
                                                  cancelButtonTitle:nil destructiveButtonTitle:destructiveButtonTitle
                                                  otherButtonTitles:button1Title, button2Title, nil];
        
        [(UIActionSheet *)self.pauseAlert showFromRect:rect inView:self.view animated:YES];
    }
    else {
        //purposely leave title off
        self.pauseAlert = [[UIAlertView alloc] initWithTitle:nil
                                                        message:nil 
                                                       delegate:self 
                                              cancelButtonTitle:destructiveButtonTitle 
                                              otherButtonTitles:button1Title, button2Title, newFilter,  nil];
        /*CGFloat rotation = DEGREES(atan2(self.view.superview.transform.b, self.view.superview.transform.a));
        CGFloat rotationAngle = 0.0;
        if (rotation >= -5 && rotation <= 5) {//Gives us a margin of error of 10, even though we shouldn't need it
            if (AppDelegate().snesControllerViewController.imageView.frame.size.height > 321) {
                rotationAngle = 90.0;
            }
        }
        else if (rotation >= 175 && rotation <= 185) {
            rotationAngle = 270.0;
        }
        alert.transform = CGAffineTransformRotate(CGAffineTransformIdentity, rotationAngle);*/
        [(UIAlertView *)self.pauseAlert show];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{	
	[self object:actionSheet clickedButtonAtIndex:buttonIndex];
	
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    [self object:alertView clickedButtonAtIndex:buttonIndex];
}

- (void)object:(id)object clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSInteger quitIndex = 0;
    NSInteger saveCurrentIndex = 1;
	NSInteger saveNewIndex = 2;
    NSInteger newFilterIndex = 3;
    NSInteger recordingIndex = 4;
    //NSInteger cancelButtonIndex = 3;
    
    /*if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        saveCurrentIndex = 0;
        saveNewIndex = 1;
        cancelButtonIndex = 2;
        quitIndex = 3;
    }*/
	
	if (buttonIndex == quitIndex) {
        NSLog(@"Quit button clicked");
		__emulation_run = 0;
//        [self performSelector:@selector(exit:) withObject:self afterDelay:1.0];
	} else if (buttonIndex == saveCurrentIndex) {
		NSLog(@"save to current file button clicked");
		__emulation_saving = 2;
	} else if (buttonIndex == saveNewIndex) {
		NSLog(@"save to new file button clicked");
		__emulation_saving = 1;
	} else if (buttonIndex == newFilterIndex) {
        [self rotateFilter];
    } else if (buttonIndex == recordingIndex) {
        if (self.isRecording) {
            [self finishRecordingVideo];
        } else {
            [self startRecordingVideo];
        }
    }
    __emulation_paused = 0;
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}


- (void)viewDidUnload {
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}




@end


