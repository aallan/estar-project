#!/usr/bin/perl

use File::Spec;
use Carp;

use XMLRPC::Lite;

my $file = File::Spec->catfile( "$ENV{HOME}", ".astrogrid-desktop" );
croak( "Unable to open file $file" ) unless open(PREFIX, "<$file" );

my $prefix = <PREFIX>;
close( PREFIX );
chomp( $prefix );

my $endpoint = $prefix . "xmlrpc";

my $rpc = new XMLRPC::Lite();
$rpc->proxy($endpoint);

my $result;
eval{ $result = $rpc->call('astrogrid.myspace.getHome' ); };
if( $@ ) {
   croak( "Can not call remote method: $@" );                      
}

unless( $result->fault() ) {
   print $result->result();
} else {
   croak( "Error (". $result->faultcode() ."):". $result->faultstring );
}

