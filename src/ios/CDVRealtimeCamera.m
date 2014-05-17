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

@implementation CDVRealtimeCamera

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
    output.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32RGBA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];

	// create a dispatch queue and associate our sample callback with it
    dispatch_queue_t queue;
    queue = dispatch_queue_create("realtime_camera_queue", NULL);
    [output setSampleBufferDelegate:(id)self queue:queue];

	// save the frame callback for use in the delegate
	self.frame_callback = command.callbackId;

	// connect the in/out pins and start running
    [self.session addInput:input];
    [self.session addOutput:output];
    [self.session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
	// lock the image buffer of the video sample
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);

	// get buffer information
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);

	// copy the raw camera data to an NSData (this will be mapped to an ArrayBuffer in JS
	NSData* data = [NSData dataWithBytes:baseAddress length:bytesPerRow * height];;

	// ok, safe to unlock the video buffer now that we've copied
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);

	// call the result callback with the image data as a buffer
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:data];
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
	[self.session stopRunning];
	self.session = nil;

	// call the frame result one more time with null as the param to indicate stoping
	CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
	[self.commandDelegate sendPluginResult:pluginResult callbackId:self.frame_callback];
	self.frame_callback = nil;

	// also send the completion result to this call's invocation callback
	[self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end