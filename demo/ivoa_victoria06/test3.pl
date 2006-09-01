#!/Software/perl-5.8.8/bin/perl

use strict;

use PGPLOT;
use File::Spec;
use Astro::FITS::CFITSIO;
use Astro::FITS::Header::CFITSIO;
use Data::Dumper;
use Starlink::AST;
use Starlink::AST::PGPLOT;


pgbegin(0,"/xs",1.5,1);
Starlink::AST::Begin();

pgpage();
pgwnad( 0,1,0,1 );


my $fc = new Starlink::AST::FitsChan( );
$fc->PutFits( "CRPIX1  = 512", 1 );
$fc->PutFits( "CRPIX2  = 256", 1 );
$fc->PutFits( "CRVAL1  = 0.0", 1 );
$fc->PutFits( "CRVAL2  = 0.0", 1 );
$fc->PutFits( "CTYPE1  = 'RA---AIT'", 1 );
$fc->PutFits( "CTYPE2  = 'DEC--AIT'", 1 );
$fc->PutFits( "CDELT1  = 0.35", 1 );
$fc->PutFits( "CDELT2  = 0.35", 1 );

$fc->Clear( "Card" );
my $wcs = $fc->Read( );

$wcs->Show();

# AST axes
# --------
my $plot = Starlink::AST::Plot->new( $wcs, 
   [0,0.1,1,0.9],[0.0, 0.0, 1024.0, 512.0], "Grid=1");

my $status = $plot->pgplot();

#$plot->Set( Colour => 2, Width => 5 );
$plot->Grid();


$plot->Set( Colour => 2, Width => 5 );

# Plot some RA/Dec points
my $ra1 = $wcs->Unformat( 1, "0:40:00" );
my $dec1 = $wcs->Unformat( 2, "41:30:00" );
my $ra2 = $wcs->Unformat( 1, "2:44:00" );
my $dec2 = $wcs->Unformat( 2, "42:00:00" );
print "\n# Current Frame " . $plot->Get( "Domain" ) . "\n";
print "# Plotting at $ra1, $dec1\n";
print "# Plotting at $ra2, $dec2\n";

$plot->Mark(24, [$ra1, $ra2],[$dec1,$dec2]);



# Done!
pgend();
exit;
