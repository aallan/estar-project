#!/home/perl/bin/perl

use Getopt::Long;
use File::Spec;
use Carp;

use Astro::Catalog;
use Astro::Catalog::Query::2MASS;
use Astro::Catalog::Query::Sesame;

unless ( scalar @ARGV >= 1 ) {
    die("USAGE: $0 -target source -radius radius [-proxy proxy]");
}

my ( %opt );
my $status = GetOptions( "target=s" => \$opt{"name"},
                         "radius=s" => \$opt{"radius"},
                         "proxy=s"  => \$opt{"proxy"} );
                         
# connection options defaults
$opt{"timeout"} = 30;
$opt{"proxy"} = "" unless defined $opt{"proxy"};

# 2MASS option defaults
$opt{"radius"} = 10 unless defined $opt{"radius"};

# default output file
$opt{"output"} = File::Spec->catfile( File::Spec->curdir(), "2mass.cat" )
                 unless defined $opt{"output"};

print " Querying Sesame Server...\n";

my $sesame_query = new Astro::Catalog::Query::Sesame(Target => $opt{"name"});
my $sesame_result; 
eval { $sesame_result = $sesame_query->querydb(); };
if ( $@ ) {
   croak("$0: Problem resolving target'". $opt{name} );
}
my $star = $sesame_result->popstar();
$opt{"ra"} = $star->ra();
$opt{"dec"} = $star->dec(); 
print "    Resolved $opt{name} to RA $opt{ra}, Dec $opt{dec}\n";

# check we have a field centre
unless ( defined $opt{"ra"} && defined $opt{"dec"} ) {
   croak("$0: Target name '". $opt{name} ."' cannot be resolved.");
}
 
# C A T A L O G U E   Q U E R Y ----------------------------------------------

print " Querying 2MASS Server...\n";

# grab catalogue 
my $twomass = new Astro::Catalog::Query::2MASS( RA     => $opt{"ra"},
                                                Dec    => $opt{"dec"},
                                                Radius => $opt{"radius"},
                                                Proxy  => $opt{"proxy"},
                                                Timeout => $opt{"timeout"} );
# query the archive   
my $catalog = $twomass->querydb();    
my $catalog_size = $catalog->sizeof();

print "    " . $catalog_size . " stars returned\n";
  
# O U T P U T   T O   F I L E ------------------------------------------------

# print header line to file
print "    Writing output file $opt{output}\n";

$status = $catalog->write_catalog( File => $opt{output}, Format => 'VOTable' );

print "    Status on write is $status\n";                  
# L A S T   O R D E R S ------------------------------------------------------

# tidy up
END {
   print " Exiting...\n";
}
                         
# Final call
exit;

# T I M E   A T   T H E   B A R  ---------------------------------------------
                         
