package eSTAR::Process;

=head1 NAME

eSTAR::Process - wrapper object to hold process related data

=head1 SYNOPSIS

  use eSTAR::Process
  
  my $process = new eSTAR::Process( $process_name );
  $process = eSTAR::Process::get_reference();
  
  $process->set_process( $process_name )
  my $version = $process->get_process()
  
  $process->set_version( $VERSION )
  my $version = $process->get_version()
  
=head1 DESCRIPTION

This module contains simpel wrapped routines to hold information
concerning the current process. Currently only holds the process
name and version for use by eSTAR::Util. This is a single instance 
object.

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT @ISA/;

@ISA = qw/Exporter/;
@EXPORT = qw/set_process get_process get_reference/;

'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

my $SINGLETON;

sub new {
   return $SINGLETON if defined $SINGLETON;

   my $proto = shift;
   my $class = ref($proto) || $proto;   
   $SINGLETON = bless { PROCESS        => undef,
                        VERSION_NUMBER => undef }, $class;
   
   $SINGLETON->set_process( @_ );
   return $SINGLETON;
}

sub get_reference {
  return $SINGLETON if defined $SINGLETON;
  return undef;
}

sub set_process {
   my $self = shift;
   $self->{PROCESS} = shift;   
}

sub get_process {
   my $self = shift;
   return $self->{PROCESS};
}   

sub set_version {
   my $self = shift;
   $self->{VERSION_NUMBER} = shift;   
}

sub get_version {
   my $self = shift;
   return $self->{VERSION_NUMBER};
}   

=back

=head1 REVISION

$Id: Process.pm,v 1.2 2004/02/21 02:56:55 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
