#!/software/perl-5.8.8/bin/perl

use SOAP::Lite;
use Data::Dumper;
use SOAP::Transport::HTTP;
use Astro::Catalog;
use Astro::Catalog::Query::USNOA2;
use Astro::Catalog::Query::GSC;
use Astro::Catalog::Query::CMC;
use Astro::Catalog::Query::SuperCOSMOS;
use Astro::Catalog::Query::2MASS;
use Astro::Catalog::Query::Sesame;
use Astro::SIMBAD::Query;

SOAP::Transport::HTTP::CGI
     ->dispatch_to('/var/www/search/soap')
     ->handle;
