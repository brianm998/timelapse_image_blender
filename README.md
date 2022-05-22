
# Timelapse Image Blender

The Timelapse Image Blender is a perl command line application which does post-processing
on timelapse image sequences.

The input sequence for the blender should be a set of tif images rendered from the original
raw camera files.  This application does not do raw to tif or jpeg conversion.

This input sequence should be in a directory that is named for the sequence, and should be
the only contentents of that sequence.

Multiple blending modes are supported.  For each mode, an output image sequence is created
from the input image sequence.  Each output frame is computed by blending one or more of
the input frames in some manner.  The different blending modes differ in how and when they
apply these blends.

The goal is to allow parts of a timelapse video that have lots of motion, like nearby water,
to be smoothed out like can be done with longer exosures.

Another application is introducting star trails to overnight timelapses.


## Installation

After downloading the application, and finding a place to put it, invoke the application as

```
./timelapse_image_blender
```
on the command line from the application directory.

It can be added to your path, or invoked from some other directory with a full pathname.

There are a number of dependencies.  The application will not startup properly with out them.

Timelapse Image Blender uses some 3rd party perl modules, and some 3rd party command line tools.

The following commands will install, or validate the presence of all of the required
3rd party perl modules:

```sudo cpan install Text::CSV
sudo cpan install Sys::Info
sudo cpan install File::Basename
sudo cpan install Term::ANSIColor
sudo cpan install Getopt::Long
```

In addition at runtime the application will validate the presence of three tools it needs
to work:

 - ffmpeg
 - ImageMagick (specifically convert)
 - exiftool

If any of these are missing, the user is directed to the proper website which should show them
how to install it for their operating system.

Once fully installed, the user will get a detailed usage statement upon running the application.


## Basic Example

Here is a basic invocation of the application:

```
timelapse_image_blender bell-curve --size 7 --max 10 --min 1 --sequence /tmp/LRT_a7riiia_100_test
```

Running like so will produce this output directory,

```
/tmp/LRT_a7riiia_100_test-bell-curve-7-way-hi-10-lo-1-merge
```

which will contain an image sequence with the same number of images as the input sequence.

It will then render that output directory into a video file named: 

```
a7riiia_100_test-bell-curve-7-way-hi-10-lo-1-merge.mov
```

as a full resolution high quality ProRes quicktime file.

Upon successful video render, the output image sequence is deleted by default.

This can be suppresssed if desired with the --no-video global option.  In that case no video
will be rendered, and the output sequence will remain.

This invocation uses a bell-curved set of weights on a window 7 frames wide, centered so that
each output frame includes the input frame of the same index at highest weight, and then
three frames before it and three frames after it with lesser weights, in a bell curve shape.

The shape of this curve can be made wider with the size parameter.  Be aware that as the
blend size of each output frame increases, so does running time.

The weights applied to the curve can be adjusted with the max and min params above.

In this example, the ends of the bell curve are weighted to be a tenth of the center,
which results in a blend for a specific output frame like this:

```11:16:44 AM - blending 7 images:
	02.88% - 01.00 - /tmp/LRT_a7riiia_100_test/LRT_00042.tiff
	10.36% - 03.59 - /tmp/LRT_a7riiia_100_test/LRT_00041.tiff
	22.33% - 07.74 - /tmp/LRT_a7riiia_100_test/LRT_00040.tiff
	28.84% - 10.00 - /tmp/LRT_a7riiia_100_test/LRT_00039.tiff
	22.33% - 07.74 - /tmp/LRT_a7riiia_100_test/LRT_00038.tiff
	10.36% - 03.59 - /tmp/LRT_a7riiia_100_test/LRT_00037.tiff
	02.88% - 01.00 - /tmp/LRT_a7riiia_100_test/LRT_00036.tiff
into
	/tmp/LRT_a7riiia_100_test-bell-curve-7-way-hi-10-lo-1-merge/LRT_00039.tif
```

These parameters can be adjusted to your liking, and can be previewd without lengthly rendering
by using the --info-only global command line arg.  When run in this mode, the application
calculates all the blendings it _would_ do, reports them, and then just exits.  This can be
helpful to see output like that above quickly, and adjust the parameters to see how it would
change without waiting a long time for the rendering.


## Supperted Blenders

There are currently four different blenders supported:

 - linear
 - bell-curve
 - smooth-ramp
 - trail-streak

Each one of them takes command line arguments after its name, and some have a different set
of arguments that they require.


### Linear Blender

The linear blender applies the same weighting to all input frames for each output frame.

This is different than the other blenders which weight the input frames differently.

While simpler than the others, this can still be useful for some timelapses.

The linear blender is best if you want a more defined transition both into and out of the blend.

### Bell Curve Blender

The bell-curve blender is similar to the linear blender, but instead weights the center
of the blend window higher than the edges.  The center of the blend window contains the
input frame with the same image sequence number as the output frame.  This has the effect
of allowing changes to fade an and out more gradually than with the linear blender.

When run with min and max values that are close to eachother, the bell-curve blender
starts to approach the same results as the linear blender.

When run with min and max values that are more than 2x different, a more pronounced blend
in and out appears.

### Smoth Ramp Blender

The smooth-ramp blender is simlar to the bell-curve blender, but instead of applying a
bell curve to the weights on the input blend window, it applies a smooth transition from one
value to another.

This can be used to avoid the smooth transition in (or out) and have a more defined transition
at either the begginning or the end of the blend.

A higher max value than min value will result in the more defined transition being at the
newest frames, and then trailing out afterwards.

A higher min value whan max value will result in the more defined transition being at the
oldest frames, and then trailing into the newer ones.

If a definied transition on both ends is desired, then the linear blender is likely best.

### Trail Streak Blender

The trail-streak blender is different than the other blenders.  It applies a more complex
input frame blend window when computing each output frame.

The effect rendered by this blender is for the ouput video to look normal until the 'start' frame.

After that, a smooth-ramp blur develops, up to 'size' frames in length.  This then trails
after the leading frame until the 'mid' frame is reached.

After the 'mid' frame, the trail starts to decrease in size until the 'end' frame is reached.

This has the effect of having the video appear normal until all of a sudden the whole frame
starts blurring a given amount, and then all of a sudden it wraps back up to normal.

A lot of non-linear curves are applied to make it look more natural.

## Author

Brian Martin

i.e. Brian in the Cloud

http://brianinthe.cloud

## Contributing

Pull requests are welcome.  


## License

[MIT](https://choosealicense.com/licenses/mit/)