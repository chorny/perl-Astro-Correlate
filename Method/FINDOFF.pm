package Astro::Correlate::Method::FINDOFF;

=head1 NAME

Astro::Correlate::Method::FINDOFF - Correlation using Starlink FINDOFF.

=head1 SYNOPSIS

  ( $corrcat1, $corrcat2 ) = Astro::Correlate::Method::FINDOFF->correlate( $cat1, $cat2 );

=head1 DESCRIPTION

This class implements catalogue cross-correlation using Starlink's FINDOFF
application.

=cut

use 5.006;
use strict;
use warnings;
use warnings::register;
use Carp;
use File::Temp qw/ tempfile /;

our $VERSION = '0.01';
our $DEBUG = 1;

=head1 METHODS

=head2 General Methods

=over 4

=item B<correlate>

Cross-correlates two catalogues.

  ( $corrcat1, $corrcat2 ) = Astro::Correlate::Method::FINDOFF->correlate( $cat1, $cat2 );

This method takes two mandatory arguments, both C<Astro::Catalog> objects.
It returns two C<Astro::Catalog> objects containing C<Astro::Catalog::Star>
objects that matched spatially between the two input catalogues. The
first returned catalogue contains matched objects from the first input
catalogue, and ditto for the second. The C<Astro::Catalog::Star> objects
in the returned catalogues are not in the original order, nor do they have
the same IDs as in the input catalogues. A matched object has the same ID
in the two returned catalogues, allowing for further comparisons between
matched objects.

=cut

sub correlate {
  my $class = shift;

  my %args = @_;
  my $cat1 = $args{'catalog1'};
  my $cat2 = $args{'catalog2'};

  # Try to find the CCDPACK binary. First, check to see if
  # the CCDPACK_DIR environment variable has been set. If it
  # hasn't, check in /star/bin/ccdpack. If that is nonexistant,
  # croak with an error.
  my $ccdpack_bin;
  if( defined( $ENV{'CCDPACK_DIR'} ) &&
      -d $ENV{'CCDPACK_DIR'} &&
      -e File::Spec->catfile( $ENV{'CCDPACK_DIR'}, "ccdpack_reg" ) ) {
    $ccdpack_bin = File::Spec->catfile( $ENV{'CCDPACK_DIR'}, "ccdpack_reg" );
  } elsif( -d File::Spec->catfile( "star", "bin", "ccdpack" ) &&
           -e File::Spec->catfile( "star", "bin", "ccdpack", "ccdpack_reg" ) ) {
    $ccdpack_bin = File::Spec->catfile( "star", "bin", "ccdpack", "ccdpack_reg" );
  } else {
    croak "Could not find CCDPACK_REG binary.\n";
  }
  print "CCDPACK_REG binary is in $ccdpack_bin\n" if $DEBUG;

  # Get two temporary file names for catalog files.
  ( undef, my $catfile1 ) = tempfile();
  ( undef, my $catfile2 ) = tempfile();

  # We need to write two input files for FINDOFF, one for each catalogue.
  # Do so using Astro::Catalog.
  $cat1->write_catalog( Format => 'FINDOFF', File => $catfile1 );
  $cat2->write_catalog( Format => 'FINDOFF', File => $catfile2 );

  # We need to write an input file for FINDOFF that lists the above two
  # input files.
  ( my $findoff_fh, my $findoff_input ) = tempfile();
  print $findoff_fh "$catfile1\n$catfile2\n";
  close $findoff_fh;

  # Set up the parameter list for FINDOFF.
  my $param = "ndfnames=false error=1 maxdisp=! minsep=5 fast=yes failsafe=yes";
  $param .= " logto=terminal namelist=! complete=0.15";
  $param .= " inlist=^$findoff_input outlist='*.off'";

  # Do the extraction.
  my $ams = new Starlink::AMS::Init(1);
  $ams->messages($DEBUG);
  my $ccdpack = new Starlink::AMS::Task( "ccdpack_reg", "$ccdpack_bin" );
  my $STATUS = $ccdpack->contactw;
  $ccdpack->obeyw("findoff", "$param");

  # Read in the first output catalog.
  my $outfile1 = $catfile1 . ".off";
  my $tempcat = new Astro::Catalog( Format => 'FINDOFF',
                                    File => $outfile1 );
  # Loop through the stars, making a new catalogue with new stars using
  # a combination of the new ID and the old information.
  my $corrcat1 = new Astro::Catalog();
  my @stars = $tempcat->stars;
  foreach my $star ( @stars ) {

    # The old ID is found in the first column of the star's comment.
    $star->comment =~ /^(\w+)/;
    my $oldid = $1;

    # Get the star's information.
    my $oldstar = $cat1->popstarbyid( $oldid );
    $oldstar = $oldstar->[0];

    # Set the ID to the new star's ID.
    $oldstar->id( $star->id );

    # And push this star onto the output catalogue.
    $corrcat1->pushstar( $oldstar );
  }

  # Do the same for the second catalogue.
  my $outfile2 = $catfile2 . ".off";
  $tempcat = new Astro::Catalog( Format => 'FINDOFF',
                                 File => $outfile2 );
  # Loop through the stars, making a new catalogue with new stars using
  # a combination of the new ID and the old information.
  my $corrcat2 = new Astro::Catalog();
  @stars = $tempcat->stars;
  foreach my $star ( @stars ) {

    # The old ID is found in the first column of the star's comment.
    $star->comment =~ /^(\w+)/;
    my $oldid = $1;

    # Get the star's information.
    my $oldstar = $cat2->popstarbyid( $oldid );
    $oldstar = $oldstar->[0];

    # Set the ID to the new star's ID.
    $oldstar->id( $star->id );

    # And push this star onto the output catalogue.
    $corrcat2->pushstar( $oldstar );
  }

  # Delete the temporary catalogues.
  unlink $catfile1 unless $DEBUG;
  unlink $catfile2 unless $DEBUG;
  unlink $outfile1 unless $DEBUG;
  unlink $outfile2 unless $DEBUG;

  return ( $corrcat1, $corrcat2 );

}

1;