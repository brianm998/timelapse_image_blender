package LinearCurve;

use strict;

# a linear curve (oxy moron, I know)
sub new {
  my ($class,
      $window_size)		# full size of the curve (one end to the other)
      = @_;

  my $self =
    {
     'name', "$window_size-way",
     };

  return bless $self, $class;
}

sub value_at_position() {
  my ($self, $position) = @_;

  return 1;
}

1;
