package eSTAR::Observation;

# ---------------------------------------------------------------------------

#+ 
#  Name:
#    eSTAR::Observation

#  Purposes:
#    Perl object to hold an ongoing observation 

#  Language:
#    Perl module

#  Description:
#    This module holds information concerning an observation request
#    and the results returned from an observation.

#  Authors:
#    Alasdair Allan (aa@astro.ex.ac.uk)

#  Revision:
#     $Id: Observation.pm,v 1.2 2005/01/19 16:57:26 aa Exp $

#  Copyright:
#     Copyright (C) 2001-2003 University of Exeter. All Rights Reserved.

#-

# ---------------------------------------------------------------------------

=head1 NAME

eSTAR::Observation - Object holding information about an observation

=head1 SYNOPSIS

  $obs = new eSTAR::Observation( ID => $unique_identity );

=head1 DESCRIPTION

Stores information about an observation, including all RTML sent or recieved
by the intelligent agent concerning the observation.

If the observation is sucessful the object will also store the FITS Headers,
Cluster Catalogue and the URL of the original FITS file.

=cut

# L O A D   M O D U L E S --------------------------------------------------

use strict;
use vars qw/ $VERSION /;

# Overloading
use overload '""' => "stringify";

use LWP::UserAgent;
use Net::Domain qw(hostname hostdomain);
use File::Spec;
use Carp;

'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

# C O N S T R U C T O R ----------------------------------------------------

=head1 REVISION

$Id: Observation.pm,v 1.2 2005/01/19 16:57:26 aa Exp $

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new instance from a hash of options

  $obs = new eSTAR::Observation( ID => $unique_id );

returns a reference to an eSTAR::Observation object

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # bless the query hash into the class
  my $block = bless { ID            => undef,
                      USERNAME      => undef,
                      PASSWORD      => undef,
                      TYPE          => undef,
                      PASSBAND      => undef,
                      STATUS        => undef,
                      NODE          => undef,               
                      SCORE_REQUEST => undef,
                      SCORE_REPLY   => {},
                      OBS_REQUEST   => undef,
                      OBS_REPLY     => undef,
                      UPDATE        => [],
                      OBSERVATION   => undef,
                      FITS_HEADER   => [],
                      CATALOG       => [],
                      FITS_URL      => [],
                      FITS_FILE     => [],
                      REFERENCE     => undef,
                      VARIABLES     => undef,
                      COLOUR_DATA   => undef,
                      CORLATE_LOG   => undef,
                      CORLATE_FIT   => undef,
                      CORLATE_HIST  => undef,
                      CORLATE_INFO  => undef,
                      FOLLOWUP      => undef,
                      FOLLOW_OBSID  => [] }, $class;

  # Configure the object
  $block->configure( @_ );

  return $block;

}

# Q U E R Y  M E T H O D S ------------------------------------------------

=back

=head2 Accessor Methods

=over 4

=item B<id>

Return (or set) the current unique ID of the obsevation

   $obs->id( $unique_id );
   $unique_id = $obs->id();

=cut

sub id {
  my $self = shift;

  if (@_) { 
    $self->{ID} = shift;
  }
  
  return $self->{ID};

} 

=item B<status>

Return (or set) the current status of the obsevation

   $obs->status( 'pending' );
   $status = $obs->status();

valid values are 'pending', 'running' or 'returned'.

=cut

sub status {
  my $self = shift;

  if (@_) { 
    $self->{STATUS} = shift;
  }
  
  return $self->{STATUS};

} 

=item B<username>

Return (or set) the username associated with the obsevation

   $obs->username( $username );
   $username = $obs->username();

=cut

sub username {
  my $self = shift;

  if (@_) { 
    $self->{USERNAME} = shift;
  }
  
  return $self->{USERNAME};

} 


=item B<password>

Return (or set) the password associated with the username

   $obs->password( $password );
   $password = $obs->password();

=cut

sub password {
  my $self = shift;

  if (@_) { 
    $self->{PASSWORD} = shift;
  }
  
  return $self->{PASSWORD};

} 

=item B<type>

Return (or set) the type of the obsevation

   $obs->type( 'SingleExposure' );
   $type = $obs->type();

valid values are 'SingleExposure', 'PhotometyFollowup' or 'AutoPhotometry'.

=cut

sub type {
  my $self = shift;

  if (@_) { 
    $self->{TYPE} = shift;
  }
  
  return $self->{TYPE};

} 

=item B<passband>

Return (or set) the passband of the obsevation

   $obs->passband( 'V' );
   $pass = $obs->passband();

=cut

sub passband {
  my $self = shift;

  if (@_) { 
    $self->{PASSBAND} = shift;
  }
  
  return $self->{PASSBAND};

} 

=item B<node>

Return the node of the obsevation should (will) be performed on

   $node = $obs->node();

=cut

sub node {
  my $self = shift;
  
  my ($node_name, $score_parsed) = $self->highest_score();
  $self->{NODE} = $node_name;
    
  return $self->{NODE};
}
 
=item B<score_request>

Return (or set) the the reference to the eSTAR::RTML::Build object which
defines the IA score request to the DN.

   $obs->score_request( $score_rtml );
   $score_rtml = $obs->score_request();


=cut

sub score_request {
  my $self = shift;

  if (@_) { 
    $self->{SCORE_REQUEST} = shift;
  }
  
  return $self->{SCORE_REQUEST};

} 

=item B<score_reply>

Return (or set) the the reference to the eSTAR::RTML::Parse objects which
defines the (all the) DN's responses too the IA's score request. 

   $obs->score_reply( $node_name, $score_parsed );
   %scores_parsed = $obs->score_reply();

where $node_name is the name of the DN that sent the score reply and
$score_parsed is the related eSTAR::RTML::Parse object.

=cut

sub score_reply {
  my $self = shift;

  if (@_) { 
    my $node_name = shift; 
    my $score_message = shift; 
    ${$self->{SCORE_REPLY}}{$node_name} = $score_message;
  }
  
  # return
  return $self->{SCORE_REPLY};

} 

=item B<highest_score>

Returns (or set) the node name and related eSTAR::RTML::Parse object for
the highest scoring score reply stored in the Observation object.

   ($node_name, $score_parsed) = $obs->highest_score();

where $node_name is the name of the DN that sent the highest scoring reply 
and $score_parsed is the related eSTAR::RTML::Parse object.

=cut

sub highest_score {
  my $self = shift;

  #print "Calling highest_score()\n\n";
  #use Carp;
  #Carp::cluck();

  # loop through the SCORE_REPLY hash and find the highest score
  my ( $node, $best_node, $highest_score );
  
  $highest_score = 0.00;
  foreach $node ( sort keys %{$self->{SCORE_REPLY}} ) {
  
    if( ${$self->{SCORE_REPLY}}{$node}->type() eq 'score' ) {
       if ( ${$self->{SCORE_REPLY}}{$node}->score() >= $highest_score  ) {
          $best_node = $node;
          $highest_score = ${$self->{SCORE_REPLY}}{$node}->score();
       }
    } 
  }
  
  # return the best node and related RTML message
  $self->{NODE} = $best_node;
  return ( $best_node, ${$self->{SCORE_REPLY}}{$best_node} );

} 


=item B<obs_request>

Return (or set) the reference to the eSTAR::RTML::Build object which
defines the IA observation request to the DN.

   $obs->obs_request( $obs_rtml );
   $obs_rtml = $obs->obs_request();


=cut

sub obs_request {
  my $self = shift;

  if (@_) { 
    $self->{OBS_REQUEST} = shift;
  }
  
  return $self->{OBS_REQUEST};

}

=item B<obs_reply>

Return (or set) the reference to the eSTAR::RTML::Parse object which
defines the DN's response too the IA's obs request

   $obs->obs_reply( $obs_parsed );
   $obs_parsed = $obs->obs_reply();


=cut

sub obs_reply {
  my $self = shift;

  if (@_) { 
    $self->{OBS_REPLY} = shift;
  }
  
  return $self->{OBS_REPLY};

} 

=item B<update>

Return (or set) the array containing the eSTAR::RTML::Parse objects which
defines the DN's observation updates

   $obs->update( $update );
   $update = $obs->update();
   @updates = $obs->update();

if called in a scalar context the first update message in the array will
be returned. NB: This is because, currently, only one frane is taken per
observation rquest so (theoretically) there will only ever be one update
message per observation request and we may as well make life as simple
as possible for ourselves.

=cut

sub update {
  my $self = shift;

  if (@_) { 
    my $update_message = shift;
    push ( @{$self->{UPDATE}}, $update_message );
  }

  return wantarray ? $self->{UDPATE} : ${$self->{UPDATE}}[0];

} 

=item B<observation>

Return (or set) the reference to the eSTAR::RTML::Parse object which
defines the DN's final 'obsevration' message to the IA

   $obs->observation( $observation );
   $observation = $observation->observation();


=cut

sub observation {
  my $self = shift;

  if (@_) { 
    $self->{OBSERVATION} = shift;
  }
  
  return $self->{OBSERVATION};

} 

=item B<fits_header>

Return (or set) the array containing the Astro::FITS::Header objects which
correspond to the the DN's observation updates

   $obs->fits_header( $hdu );
   $hdu = $obs->fits_header();
   @hus = $obs->fits_header();

if called in a scalar context the first Header object in the array will
be returned. NB: This is because, currently, only one frane is taken per
observation rquest so (theoretically) there will only ever be one update
message per observation request and we may as well make life as simple
as possible for ourselves.

=cut

sub fits_header {
  my $self = shift;

  if (@_) { 
    my $fits_header = shift;
    push ( @{$self->{FITS_HEADER}}, $fits_header );
  }

  return wantarray ? $self->{FITS_HEADER} : ${$self->{FITS_HEADER}}[0];

} 

=item B<catalog>

Return (or set) the array containing the Astro::Catalog objects which
correspond to the the DN's observation updates

   $obs->catalog( $cluster_catalog );
   $cluster_catalog = $obs->catalog();
   @catalogs = $obs->catalog();

if called in a scalar context the first Catalog object in the array will
be returned. NB: This is because, currently, only one frane is taken per
observation rquest so (theoretically) there will only ever be one update
message per observation request and we may as well make life as simple
as possible for ourselves.

=cut

sub catalog {
  my $self = shift;

  if (@_) { 
    my $cluster_catalog = shift;
    push ( @{$self->{CATALOG}}, $cluster_catalog );
  }

  return wantarray ? $self->{CATALOG} : ${$self->{CATALOG}}[0];

} 

=item B<fits_url>

Return (or set) the array containing URLs pointing the the FITS data files 
whichcorrespond to the the DN's observation updates

   $obs->fits_url( $url );
   $url = $obs->fits_url();
   @urls = $obs->fits_url();

if called in a scalar context the first URL in the array will be returned.
NB: This is because, currently, only one frane is taken per observation 
rquest so (theoretically) there will only ever be one update message per
observation request and we may as well make life as simple as possible for
ourselves.

=cut

sub fits_url {
  my $self = shift;

  if (@_) { 
    my $url = shift;
    push ( @{$self->{FITS_URL}}, $url );
  }

  return wantarray ? $self->{FITS_URL} : ${$self->{FITS_URL}}[0];

} 

=item B<fits_file>

Return (or set) the array containing path to the local copy of the FITS data
files which correspond to the the DN's observation updates

   $obs->fits_file( $url );
   $file_name = $obs->fits_file();
   @files = $obs->fits_file();

if called in a scalar context the first path in the array will be returned.
NB: This is because, currently, only one frane is taken per observation 
rquest so (theoretically) there will only ever be one update message per
observation request and we may as well make life as simple as possible for
ourselves.

=cut

sub fits_file {
  my $self = shift;

  if (@_) { 
    my $file_name = shift;
    push ( @{$self->{FITS_FILE}}, $file_name );
  }

  return wantarray ? $self->{FITS_FILE} : ${$self->{FITS_FILE}}[0];

} 

=item B<summary>

Return a summary of the object as plain text, note that the summary is
not terminated by a carriage return.

=cut

sub summary {
  my $self = shift;
 
  my $score = 'NOT SCORED';
  if( scalar %{$self->{SCORE_REPLY}} ) {
      my ($node_name, $score_parsed) = $self->highest_score();
      if ( defined $score_parsed ) {
         $score = $score_parsed->score();
      } elsif ( $self->status() eq 'reject' ) {
         $score = "REJECTED";
      } else { 
         $score = "NOT SCORED";
      } 
      
      if ( $self->status() eq 'fits problem' ) {
         $score = "BAD FITS HDU";
      }   
          
  }
  
  # build string
  my $string;
  
  # PENDING
  if ( $self->status() eq "pending" ) {
  
      unless ( $self->type() =~ "Followup" ) {

        # build string
        $string = " " . $self->{ID} . "   " . $self->{SCORE_REQUEST}->target() .
                  "   (" . $self->{TYPE} . ")    " . $score;
   
      } else {
   
        # build string
        $string = " " . $self->{ID} . "   " . $self->{SCORE_REQUEST}->target() .
                  "   (" . $self->{TYPE} . " " . $self->{FOLLOWUP}. ")    " .
                  $score;   
   
      }
  }
    
  # REJECTED            
  elsif ( $self->status() eq "reject" ) {
 
     # build string
     $string = " " . $self->{ID} . "   " . $self->{SCORE_REQUEST}->target() .
               " " . $score; 
  
  } 
  
  # RETURNED
  elsif ( $self->status() eq "returned" ) {
  
     if ( $self->status() eq 'fits problem' ) {
        $string = " " . $self->{ID} . "   " .  
                  $self->{SCORE_REQUEST}->target() . "   (" . 
                  $self->{TYPE} . ")    " . $score;  
     } else {
     
       if( $self->type() =~ "Followup" ) {
           my $list = "";
           foreach my $i ( 0 ... $#{$self->{FOLLOW_OBSID}} ) {
              my $id = ${$self->{FOLLOW_OBSID}}[$i];
              $_ = $id;
              /^(\d+)/;
              my $number = $1;
              $list = $list . $number . " ";
           }
               
           # Monitor requests have the number of followup observations tagged
           $string = " " . $self->{ID} . "   " . 
                     $self->{SCORE_REQUEST}->target() . " + " . $list;  
       
       } elsif( $self->type() =~ "Automatic" ) { 
           # Monitor requests have the number of followup observations tagged
           $string = " " . $self->{ID} . "   " . 
                     $self->{SCORE_REQUEST}->target() . " (Automatic)";        
       
       } else {
           # Monitor requests have the number of followup observations tagged
           $string = " " . $self->{ID} . "   " . 
                     $self->{SCORE_REQUEST}->target() . " (" . $self->{TYPE} .
                      ")    " . $self->{NODE};        
       }               
     }  
  
  # OTHERWISE
  } else {
    
      if ( $self->status() eq 'fits problem' ) {
        
        $string = " " . $self->{ID} . "   " . 
                  $self->{SCORE_REQUEST}->target() . "   (" . 
                  $self->{TYPE} . ")    " . $score;          
      } else {
   
        if( $self->type() =~ "Followup" ) {
          $string = " " . $self->{ID} . "   " . 
                     $self->{SCORE_REQUEST}->target() . "   (" . $self->{TYPE} .
                      " " . $self->{FOLLOWUP}  . ")    " . $self->{NODE};    
        } else {
           $string = " " . $self->{ID} . "   " . 
                     $self->{SCORE_REQUEST}->target() .
                     "   (" . $self->{TYPE} . ")    " . $self->{NODE};       
        }     
      }
  }
  
  return $string;
}

=item B<reference_catalog>

Return (or set) the reference to the Astro::Catalog object contatining the
reference catalog for this observation, this is only created for obsevations
of type PhotometyFollowup

   $obs->reference_catalog( $catalog );
   $catalog = $observation->reference_catalog();


=cut

sub reference_catalog {
  my $self = shift;

  if (@_) { 
    $self->{REFERENCE} = shift;
  }
  
  return $self->{REFERENCE};

} 

=item B<varaiable_catalog>

Return (or set) the varaibales to the Astro::Catalog object contatining the
reference catalog for this observation, this is only created for obsevations
of type PhotomteryFollowup

   $obs->varaiable_catalog( $catalog );
   $catalog = $observation->variable_catalog();


=cut

sub variable_catalog {
  my $self = shift;

  if (@_) { 
    $self->{VARIABLES} = shift;
  }
  
  return $self->{VARIABLES};

} 

=item B<data_catalog>

Return (or set) the colour data to the Astro::Catalog object contatining the
reference catalog for this observation, this is only created for obsevations
of type PhotomteryFollowup

   $obs->data_catalog( $catalog );
   $catalog = $observation->data_catalog();


=cut

sub data_catalog {
  my $self = shift;

  if (@_) { 
    $self->{COLOUR_DATA} = shift;
  }
  
  return $self->{COLOUR_DATA};

} 

=item B<corlate_log>

Return (or push) the corlate log file into the object

   $obs->corlate_log( $scalar );
   $scalar = $observation->corlate_log();


=cut

sub corlate_log {
  my $self = shift;

  if (@_) { 
    $self->{CORLATE_LOG} = shift;
  }
  
  return $self->{CORLATE_LOG};

} 

=item B<corlate_fit>

Return (or push) the corlate fit file into the object

   $obs->corlate_fit( $scalar );
   $scalar = $observation->corlate_fit();


=cut

sub corlate_fit {
  my $self = shift;

  if (@_) { 
    $self->{CORLATE_FIT} = shift;
  }
  
  return $self->{CORLATE_FIT};

} 

=item B<corlate_hist>

Return (or push) the corlate histogram file into the object

   $obs->corlate_hist( $scalar );
   $scalar = $observation->corlate_hist();


=cut

sub corlate_hist {
  my $self = shift;

  if (@_) { 
    $self->{CORLATE_HIST} = shift;
  }
  
  return $self->{CORLATE_HIST};

}

=item B<corlate_info>

Return (or push) the corlate information file into the object

   $obs->corlate_info( $scalar );
   $scalar = $observation->corlate_info();


=cut

sub corlate_info {
  my $self = shift;

  if (@_) { 
    $self->{CORLATE_INFO} = shift;
  }
  
  return $self->{CORLATE_INFO};

} 

=item B<followup>

Return (or push) the number of followup observations to make if this
is a monitoring observation

   $obs->followup( 10 );
   $number = $observation->followup();


=cut

sub followup {
  my $self = shift;

  if (@_) { 
    $self->{FOLLOWUP} = shift;
  }
  
  return $self->{FOLLOWUP};

} 

=item B<followup_id>

Return (or push) the IDs of followup observations steming from this
observation, only valid for observations of type PhotomteryFollowup

   $obs->followup_id( $id );
   @observations = $observation->followup_id();


=cut

sub followup_id {
  my $self = shift;

  if (@_) { 
    my $obs_id = shift;
    push ( @{$self->{FOLLOW_OBSID}}, $obs_id );
  }
  
  return @{$self->{FOLLOW_OBSID}};

} 

# C O N F I G U R E -------------------------------------------------------

=back

=head2 General Methods

=over 4

=item B<configure>

Configures the object, takes an options hash as an argument

  $obs->configure( %options );

Does nothing if the array is not supplied.

=cut

sub configure {
  my $self = shift;

  # CONFIGURE FROM ARGUEMENTS
  # -------------------------

  # return unless we have arguments
  return undef unless @_;

  # grab the argument list
  my %args = @_;

  # Loop over the allowed keys and modify the default query options
  for my $key (qw / ID / ) {
      my $method = lc($key);
      $self->$method( $args{$key} ) if exists $args{$key};
  }

}

=item B<stringify>

Method called automatically when the object is printed in
a string context. Simple invokes the C<summary()> method with
default arguments.

=cut

sub stringify {
  my $self = shift;
  return $self->summary();
}

# T I M E   A T   T H E   B A R  --------------------------------------------

=back

=head1 COPYRIGHT

Copyright (C) 2001-2003 University of Exeter. All Rights Reserved.

This program was written as part of the eSTAR project and is free software;
you can redistribute it and/or modify it under the terms of the GNU Public
License.

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>,

=cut

# L A S T  O R D E R S ------------------------------------------------------

1;                                                                  
