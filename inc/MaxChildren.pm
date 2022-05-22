package MaxChildren;

use strict;

# the filename for an image and a weight for it
sub new($$$) {
  my ($class, $filename, $default) = @_;
  my $self = {
      'filename' => $filename,
      'default' => $default,
  };

  return bless $self, $class;
}

sub currentValue() {
  my ($self) = @_;

  my $filename = $self->{filename};

  unless(-e $filename) {
#    warn "current value file $filename does not exist, returning max children ", $self->{default}, "\n";
    return $self->{default};
  }

  open my $fh, $filename;
  my $value = <$fh>;
  if($value =~ /(\d+)/) {
    return $1;
  }

  return $self->{default};
}

1;
