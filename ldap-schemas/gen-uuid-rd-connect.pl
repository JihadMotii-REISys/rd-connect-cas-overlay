#!/usr/bin/perl -w


use strict;

use bignum qw(hex);
use Carp;
use UUID::Tiny ':std';

Carp::croak("You need to install Digest::SHA or Digest::SHA1 in order to use this program")  unless(UUID_SHA1_AVAIL);

my $DNSdomain = 'rd-connect.eu';
my $rdconnectUUID = create_uuid(UUID_V5,UUID_NS_DNS,$DNSdomain);
my $rdconnectUUID_string = uuid_to_string($rdconnectUUID);
my $rdconnectUUID_strnumber = $rdconnectUUID_string;
$rdconnectUUID_strnumber =~ tr/-//d;
my $rdconnectUUID_number = hex($rdconnectUUID_strnumber);

# LDAP OIDs on 2.25 subtree are based on UUIDs
# http://www.oid-info.com/get/2.25
print "DNS domain\t$DNSdomain\n";
print "UID\t",$rdconnectUUID_string,"\n";
print "LDAP OID\t2.25.$rdconnectUUID_number\n";
