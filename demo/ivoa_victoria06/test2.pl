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

pgpage();
pgwnad( 0,1,0,1 );


# Change FrameSet
# ---------------
my $wcs = new Starlink::AST::SkyFrame( "" );

#$wcs->Set( System => "ECLIPTIC" );
$wcs->Show();

# AST axes
# --------
my $plot = Starlink::AST::Plot->new( $wcs, 
   [0,0,1,1],[0,0, 1, 1], "Grid=1");

my $status = $plot->pgplot();

$plot->Set( Colour => 2, Width => 5 );
$plot->Grid();


# Done!
pgend();
exit;
