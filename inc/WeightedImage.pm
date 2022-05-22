package WeightedImage;

use strict;

# the filename for an image and a weight for it
sub new {
  my ($class, $image_filename, $weight) = @_;
  my $self =
    {
     'filename', $image_filename,
     'weight', $weight,
    };

  return bless $self, $class;
}

sub description() {
  my ($self, $total_weight) = @_;

  my $weight = sprintf("%05.2f", $self->{weight});

  if(defined $total_weight) {
    my $percentage = sprintf("%05.2f", $self->{weight}/$total_weight*100);
    return $percentage."%"." - ".$weight." - ".$self->{filename};
  } else {
    return $weight." - ".$self->{filename};
  }
}

1;
