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

RealtimeCamera =
{
	/**
	 * Begin a camera capture session
	 * @param resolution One of the following strings: [ "352x288", "640x480", "1280x720", "1920x1080" ]
	 * @param on_frame Callback which is invoked
	 */
	start: function(resolution, on_frame, on_error) {
		cordova.exec(
			on_frame,
			on_error,
			"RealtimeCamera",
			"startCapture",
			[ resolution ]
		);
	},
	/**
	 * Stop a running camera capture session. This results in the on_frame callback firing one more time with null as the param.
	 */
	stop: function() {
		cordova.exec(
			function(winParam) {},
			function(err) {},
			"RealtimeCamera",
			"endCapture",
			[]
		);
	},
};