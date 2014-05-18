/**
The MIT License (MIT)

Copyright (c) 2014 Clark/Nikdel/Powell

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
#import "CDVRealtimeCamera.h"
#import <Cordova/CDV.h>
#import <JavaScriptCore/JavaScriptCore.h>

#define SEND_USING_JSCONTEXT 0
#define DEBUG_FRAMERATE 0

@implementation CDVRealtimeCamera

- (void)changeResolution:(CDVInvokedUrlCommand*)command
{
	// a session has already started
	if (self.session == nil)
	{
		CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No capture session is running."];
		[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		return;
	}

	// set the capture session resolution
	NSString* sessionPreset = nil;
    id resolutionParam = [command.arguments objectAtIndex:0];
	if ([resolutionParam isEqualToString:@"352x288"])
		sessionPreset = AVCaptureSessionPreset352x288;
	else if ([resolutionParam isEqualToString:@"640x480"])
		sessionPreset = AVCaptureSessionPreset640x480;
	else if ([resolutionParam isEqualToString:@"1280x720"])
		sessionPreset = AVCaptureSessionPreset1280x720;
	else if ([resolutionParam isEqualToString:@"1920x1080"])
		sessionPreset = AVCaptureSessionPreset1920x1080;
	else
	{
		CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unsupported resolution setting."];
		[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		return;
	}

	// change the preset in a background thread
	[self.commandDelegate runInBackground:^{
		if (self.session != nil) {
			self.session.sessionPreset = sessionPreset;
		}
	}];

	// send the response
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
	[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startCapture:(CDVInvokedUrlCommand*)command
{
	// a session has already started
	if (self.session != nil)
	{
		CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Capture session is already running."];
		[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		return;
	}
	
	// set up a new av capture session
    self.session = [[AVCaptureSession alloc] init];

	// set the capture session resolution
    id resolutionParam = [command.arguments objectAtIndex:0];
	if ([resolutionParam isEqualToString:@"352x288"])
		self.session.sessionPreset = AVCaptureSessionPreset352x288;
	else if ([resolutionParam isEqualToString:@"640x480"])
		self.session.sessionPreset = AVCaptureSessionPreset640x480;
	else if ([resolutionParam isEqualToString:@"1280x720"])
		self.session.sessionPreset = AVCaptureSessionPreset1280x720;
	else if ([resolutionParam isEqualToString:@"1920x1080"])
		self.session.sessionPreset = AVCaptureSessionPreset1920x1080;
	else
	{
		CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Unsupported resolution setting."];
		[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		return;
	}

	// get the default video device and retrieve its input pin
    AVCaptureDevice* device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];

	// output our video data to a buffer in 32RGBA format (should match CanvasPixelArray format)
    AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];
    output.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];

	// create a dispatch queue and associate our sample callback with it
    dispatch_queue_t queue = dispatch_get_main_queue();//dispatch_queue_create("realtime_camera_queue", NULL);
    [output setSampleBufferDelegate:(id)self queue:queue];

	// save the frame callback for use in the delegate
	self.frame_callback = command.callbackId;

	// keep a frame buffer around so we can avoid memory thrashing
	self.frame_buffer = [NSMutableData data];

	// connect the in/out pins and start running
    [self.session addInput:input];
    [self.session addOutput:output];
	[self.session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
#if DEBUG_FRAMERATE
	static int gFrameNum = 0;
	NSLog(@"Frame %d", gFrameNum++);
#endif

#if SEND_USING_JSCONTEXT
	JSContext *ctx = [self.webView valueForKeyPath:@"documentView.webView.mainFrame.javaScriptContext"];
	if (ctx == nil)
		return;
	JSValue *apiObj = ctx[@"RealtimeCamera"];
	if (![apiObj isObject])
		return;
	JSValue *outData = apiObj[@"_framebuffer"];
	// we have this typedarray now but there doesn't seem to be any way to manipulate it using the public API :-(
	JSValue *outContext = apiObj[@"_context"];
	// another alternative would be to set the pixel data on the context directly. Again not seeing a way to get access to the right headers to do this though :-(
#endif

	// lock the image buffer of the video sample
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);

	// get buffer information
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);

	// copy the raw camera data to an NSData (this will be mapped to an ArrayBuffer in JS
	// swizzle to RGBA and flip height
	[self.frame_buffer setLength:bytesPerRow * height];
	uint8_t *destAddress = (uint8_t*)[self.frame_buffer mutableBytes];
	for (size_t i=0;i<height;++i)
	{
		uint8_t* row_start = baseAddress + i * bytesPerRow;
		uint8_t* dst_row = destAddress + i * bytesPerRow;
		for (size_t j=0;j<width;++j)
		{
			uint8_t* px_start = row_start + j * 4;
			*(dst_row++) = *(px_start + 2);
			*(dst_row++) = *(px_start + 1);
			*(dst_row++) = *(px_start + 0);
			*(dst_row++) = *(px_start + 3);
		}
	}

	// ok, safe to unlock the video buffer now that we've copied
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
	
#if SEND_USING_JSCONTEXT
	// use the JSContext to set a global array buffer (this is much faster than using messageAsArrayBuffer as the latter serializes the
	// data to base64, then JSON, and back.

	//outData


	// just send an empty event telling the app to pull the buffer
	NSArray* params = [NSArray arrayWithObjects: [NSNumber numberWithInteger:width], [NSNumber numberWithInteger:height], nil];
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
#else
	// call the result callback with the image data as a buffer
	NSArray* params = [NSArray arrayWithObjects: [NSNumber numberWithInteger:width], [NSNumber numberWithInteger:height], self.frame_buffer, nil];
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsMultipart: params ];
#endif
	[pluginResult setKeepCallbackAsBool:YES]; // keep the callback so we can use it again
	[self.commandDelegate sendPluginResult:pluginResult callbackId:self.frame_callback];
}

- (void)endCapture:(CDVInvokedUrlCommand*)command
{
	if (self.session == nil)
	{
		CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No capture session is currently running."];
		[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
		return;
	}

	// tear down the capture session
	AVCaptureSession* sessionRef = self.session;
	NSString* frameCallback = self.frame_callback;
	self.session = nil;
	self.frame_callback = nil;
	
	// stop running
	[sessionRef stopRunning];

	// call the frame result one more time with false as the param to indicate stoping
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
	[self.commandDelegate sendPluginResult:pluginResult callbackId:frameCallback];
	// also send the completion result to this call's invocation callback
	[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end