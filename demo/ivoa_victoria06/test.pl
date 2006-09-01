#!/Software/perl-5.8.8/bin/perl

use strict;

use PGPLOT;
use File::Spec;
use Astro::FITS::CFITSIO;
use Astro::FITS::Header::CFITSIO;
use Data::Dumper;
use Starlink::AST;
use Starlink::AST::PGPLOT;


pgbegin(0,"/xs",1,1);
Starlink::AST::Begin();

# FITS File
# ---------
my $file = File::Spec->catfile( "cobe.fit" );
#my $file = File::Spec->catfile( "iras-b1-allsky.fits" );

# Get FITS Header
# ---------------

my $header = new Astro::FITS::Header::CFITSIO( File => $file );
my @cards = $header->cards();

# Make FitsChan
# -------------
my $wcsinfo;
if ($header->can("get_wcs")) {
  $wcsinfo = $header->get_wcs();
} else {
  # Use fallback position
  $wcsinfo = get_wcs( $header );
}

# Set up window
# -------------
my $nx = $header->value("NAXIS1");
my $ny = $header->value("NAXIS2");
pgpage();
pgwnad( 0,1,0,1 );

my ( $x1, $x2, $y1, $y2 ) = (0,1,0,1);

my $xscale = ( $x2 - $x1 ) / $nx;
my $yscale = ( $y2 - $y1 ) / $ny;
my $scale = ( $xscale < $yscale ) ? $xscale : $yscale;
my $xleft   = 0.5 * ( $x1 + $x2 - $nx * $scale );
my $xright  = 0.5 * ( $x1 + $x2 + $nx * $scale );
my $ybottom = 0.5 * ( $y1 + $y2 - $ny * $scale );
my $ytop    = 0.5 * ( $y1 + $y2 + $ny * $scale );

# Read data 
# ---------
my $array = read_file( $file );
         
pggray( $array, $nx, $ny, 1, $nx, 1, $ny, 500, 0, 
  [ $xleft-0.5*$scale, $scale, 0.0, $ybottom-0.5*$scale, 0.0, $scale ] );

# Change FrameSet
# ---------------
#$wcsinfo->Set( System => "GALACTIC" );

$wcsinfo->Show();

# AST axes
# --------
my $plot = Starlink::AST::Plot->new( $wcsinfo, 
   [$xleft,$ybottom,$xright,$ytop],[0.5,0.5, $nx+0.5, $ny+0.5], "Grid=1");

my $status = $plot->pgplot();

#$plot->Set( Colour => 2, Width => 5 );
$plot->Grid();


# Done!
pgend();
sleep(2);
exit;

sub read_file {
   my $file = shift;

   my $status = 0;
   my $fptr = Astro::FITS::CFITSIO::open_file(
             $file, Astro::FITS::CFITSIO::READONLY(), $status);

   my $naxes;
   $fptr->get_img_parm(undef, undef, $naxes, $status);
   print "Image: ${$naxes}[0] x ${$naxes}[1]\n";

   my ($array, $nullarray, $anynull);
   $fptr->read_pixnull( 
     Astro::FITS::CFITSIO::TDOUBLE(), [1,1], ${$naxes}[0]*${$naxes}[1], 
     $array, $nullarray, $anynull ,$status);
   $fptr->close_file($status);

   return $array;
}

# Implementation of the get_wcs method for old versions of Astro::FITS::Header

sub get_wcs {
  my $self = shift;
  my $fchan = Starlink::AST::FitsChan->new();
  for my $i ( $self->cards() ) {
    $fchan->PutFits( $i, 0);
  }
  $fchan->Clear( "Card" );
  return $fchan->Read();
}
