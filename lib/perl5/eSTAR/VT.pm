package eSTAR::VT;

=head1 NAME

eSTAR::VT - Virtual Telescope base class.

=over 4

=cut

use strict;
use warnings;

use lib $ENV{ESTAR_PERL5LIB};

use Astro::Telescope;
use Astro::Coords;


sub new {
   my ( $class, $tel_name, @tel_params ) = @_;

   my $self = bless {}, $class;


   # Set some possible default telescope locations...
   my %attrs_for = ( 
                     'lt' => {
                              name => 'Virtual LT',
                              long => 5.97113454, 
                              lat  => 0.502001024,
                              alt  => 2344,
                             },
                     'ftn' => {
                               name => 'Virtual FTN',                     
                               long => 3.55604516, 
                               lat  => 0.362078821,
                               alt  => 3055,
                              },
                     'fts' => {
                               name => 'Virtual FTS',
                               long => 2.60153048, 
                               lat  => -0.54577638,
                               alt  => 1150,
                              }                             
                    );
    
    my ($name, $long, $lat, $alt);
    
   # If this is a telescope we know the location of...
   if ( defined $attrs_for{$tel_name} ) {
   
   ($name, $long, $lat, $alt) = (
                                  $attrs_for{$tel_name}->{name}, 
                                  $attrs_for{$tel_name}->{long},
                                  $attrs_for{$tel_name}->{lat},
                                  $attrs_for{$tel_name}->{alt}
                                 );   

   }
   else {
      # Check we have enough custom arguments for a non-default telescope...
      croak("Not enough params provided to instantiate virtual telescope!")
         if ( scalar @tel_params < 4 );
      
      ($name, $long, $lat, $alt) = @tel_params;
      
   }

   #...instantiate an Astro::Telescope object...
   
   $self->{tel} = new Astro::Telescope(Name => $name, Long => $long, 
                                       Lat  => $lat,  Alt  => $alt);


   return $self;
}


sub get_telescope {
   my $self = shift;

   return $self->{tel};
}


sub is_dark {
   my $self = shift;
   my $time = shift;
   
   my $sun = new Astro::Coords(planet => 'sun');
   $sun->datetime( $time );
   $sun->telescope( $self->{tel} );

   my $sunrise = $sun->rise_time( horizon => Astro::Coords::AST_TWILIGHT );
   my $sunset  = $sun->set_time( horizon => Astro::Coords::AST_TWILIGHT );
   
   if ( $sunrise < $sunset ) {
      return wantarray() ? (1, $sunrise) : 1;
   }
   else {
      return wantarray() ? (0, $sunset) : 0;
   }
}


sub is_within_limits {
   my $self = shift;
   my $target_el = shift;

   my $min_el = new Astro::Coords::Angle(30, units => 'deg');

   return ( $target_el > $min_el ) ? 1 : 0;
}


=back


=head1 AUTHORS

Eric Saunders E<lt>saunders@astro.ex.ac.ukE<gt>

=cut

1;
