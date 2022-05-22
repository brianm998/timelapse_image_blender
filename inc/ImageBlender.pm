package ImageBlender;

use strict;
use POSIX ":sys_wait_h";
use WeightedImage;
use Log qw(logSystem timeLog);
use Term::ANSIColor qw(:constants);

# This class takes a list of source frames as WeightedImage objects,
# and blends them into the given output_filename.
# The main work here is constructing the single convert commandline which
# blends the given source frames according to their given weights into the output file.
# This is all run as a single command.

# this class doesn't work without the convert command from imagemagick
sub validate() {
  # we need convert (ImageMagick)

  die <<END
ERROR

ImageMagick is not installed

visit https://imagemagick.org

and install it to use this tool
END
    unless(system("which convert >/dev/null") == 0);
}

# construct a new instance with a given output filename, and empty list of source images
sub new {
  my ($class, $output_filename) = @_;
  my $self =
    {
     'output_filename', $output_filename, # the filename to write the blended image to
     'image_list', [],		# a list of WeightedImage objects
    };

  return bless $self, $class;
}

sub numberOfImages() {
  my ($self) = @_;

  return scalar(@{$self->{image_list}});
}

# pull the next image off the list
sub nextImage() {
  my ($self) = @_;

  return shift @{$self->{image_list}};
}

sub setImageList() {
  my ($self, $image_list) = @_;

  foreach my $image (@$image_list) {
    $self->addImage($image);
  }
}

# adds a weighted image to the list
sub addImage() {
  my($self, $image) = @_;

  unshift @{$self->{image_list}}, $image;
}

# adds a weighted image to the list
sub add() {
  my($self, $filename, $weight) = @_;

  $self->addImage(WeightedImage->new($filename, $weight));
}

# this is here so that ImageBlender adheres to what Forker needs to run it
sub execute() {
  my ($self) = @_;

  $self->blend_images();
}

# destructive method which renders to the output file with a single shell command
sub blend_images() {
  my ($self) = @_;

  my $total_weight = 0;
  foreach my $image (@{$self->{image_list}}) {
    $total_weight += $image->{weight};
  }

  my @FF = map { $_->description($total_weight); } @{$self->{image_list}};

  timeLog(
      MAGENTA, "blending ", BLUE, ,$self->numberOfImages(),
      " images:\n\t",RESET, join("\n\t", @FF),MAGENTA,
      "\ninto\n\t", BLUE,$self->{output_filename}, "\n", RESET
  );

  if($self->numberOfImages() == 1) {
    # if we are only blending one image, simply copy it and be done
    # source image and dest should be on same filesystem, so ln should be fast
    my $image = $self->nextImage();
    ln_or_cp($image->{filename}, $self->{output_filename});
    return;
  }

  # start to assemble the convert command line
  my $cmd = "convert ";

  # grab the first two images, removing them from the list
  my $image_1 = $self->nextImage();
  my $image_2 = $self->nextImage();

  # and their weights
  my $weight_1 = $image_1->{weight};
  my $weight_2 = $image_2->{weight};

  # calculate blend percentages
  my $percentage_1 = $weight_1 / ($weight_1 + $weight_2) * 100;
  my $percentage_2 = $weight_2 / ($weight_1 + $weight_2) * 100;

  # the convert command expects the first two images like this
  $cmd .= $image_1->{filename};
  $cmd .= " ";
  $cmd .= $image_2->{filename};
  $cmd .= " -compose blend -define compose:args=$percentage_1"."x"."$percentage_2  -composite ";

  my $previous_weight = $weight_1+$weight_2;

  # any subsequent images need to be added to the command line individually
  while($self->numberOfImages() > 0) {
    # grab the next image, removing it from the list
    my $next_image = $self->nextImage();

    # and its weight
    my $next_weight = $next_image->{weight};

    # calculate blend percentages
    my $next_image_blend_percentage = $next_weight / ($next_weight + $previous_weight) * 100;
    my $previous_blend_percentage = $previous_weight / ($next_weight + $previous_weight) * 100;

    $cmd .= $next_image->{filename};
    $cmd .= " -compose blend -define compose:args=";
    $cmd .= $next_image_blend_percentage."x".$previous_blend_percentage;
    $cmd .= " -composite ";

    $previous_weight += $next_weight;
  }

  $cmd .= $self->{output_filename};

  timeLog("starting render of ", $self->{output_filename});

  my $start_time = time;

  if(system($cmd) != 0) {	# don't log this directly, it can get ginormous
      warn "render of "+$self->{output_filename}+" failed: $!\n";
      die "failed: $!\n";
  }

  my $end_time = time;

  timeLog("render of ", $self->{output_filename}, " complete, took ",($end_time-$start_time), " seconds");
}

# try to make a hard link instead of copying
sub ln_or_cp() {
  my($source_file, $dest_file) = @_;

  # if both are on same filesystem, ln will work, and is a fast metadata update.
  unless(logSystem("ln $source_file $dest_file") == 0) {
    # if ln fails, then just go ahead and copy it.  Slower, but should work.
    return logSystem("cp $source_file $dest_file")
  }

  return 0;
}

sub logImageBlenderList($) {
  my ($image_blender_list) = @_;

  foreach my $image_blender (@$image_blender_list) {

    my $total_weight = 0;
    foreach my $image (@{$image_blender->{image_list}}) {
      $total_weight += $image->{weight};
    }

    my @FF = map { $_->description($total_weight); } @{$image_blender->{image_list}};

    print "blending ",$image_blender->numberOfImages(),
			       " images:\n\t", join("\n\t", @FF),
			       "\ninto\n\t", $image_blender->{output_filename}, "\n", 
			      ;

  }
}

1;


