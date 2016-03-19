#!/usr/bin/perl

use warnings;
use strict;

use POSIX qw(ceil);
use Data::Dumper;
use MIME::Base64;
use JSON -support_by_pp;
use LWP;
use Carp;
use Getopt::Long;
use Pod::Usage;
use English qw (-no_match_vars);

local $OUTPUT_AUTOFLUSH = 1;
local $ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

$JSON::PP::true      = 1;
$JSON::PP::false     = 0;
$Data::Dumper::Terse = 1;    # do not print dumper $VARx

sub main {
    my $user     = 'admin';
    my $password = 'admin';
    my $host     = 'localhost:8443';
    my $uuid;
    my $timeout = 3600;
    my $inputs;
    my $help;
    my $verbose = 0;
    my $encode  = 0;
    my $authorization;
    my $credentials;
    my $heartbeat = 120;
    my $name;
    my $async = 0;

    while (
        !GetOptions(
            'user=s'        => \$user,
            'password=s'    => \$password,
            'host=s'        => \$host,
            'uuid=s'        => \$uuid,
            'name=s'        => \$name,
            'encode=s'      => \$encode,
            'credentials=s' => \$credentials,
            'verbose'       => \$verbose,
            'input=s%'      => \$inputs,
            'timeout=i'     => \$timeout,
            'heartbeat=i'   => \$heartbeat,
            'async'         => \$async,
            'help|h|?'      => \$help
        )
      )
    {
        pod2usage(2);
    }
    pod2usage(1) if $help;

    if ($encode) {
        print scalar encode_base64($encode);
        return;
    }

    if ($credentials) {
        $authorization = "Basic $credentials";
    }
    else {
        $authorization =
          "Basic " . scalar encode_base64( $user . ':' . $password );
    }

    pod2usage() if ( !$uuid );

    my $ua = LWP::UserAgent->new( keep_alive => 1 );

    $ua->env_proxy;
    $ua->default_header( 'Authorization' => $authorization );

    my ( $run_id, $status, $flow_result );

    $run_id = run_flow( $ua, $host, $uuid, $inputs );
    
    #exit if async otherwise wait for flow to finish and return the result
    if ($async) { 
        return 0; 
    }
    
    $status = track_flow( $ua, $host, $run_id, $timeout, $heartbeat );
    $flow_result = collect_result( $ua, $host, $run_id );
    
    if ($verbose) {
        print JSON->new->pretty->encode($flow_result);
    }
    else {      
        
        if ( $flow_result->{'flowOutput'} ) {
            foreach (keys %{ $flow_result->{'flowOutput'} }) {
                print "$_=$flow_result->{'flowOutput'}->{$_}\n";
            }          
        }

        if ($status) {
            print "Status=$status\n"
        }
    }

    if ( $status && $status eq 'RESOLVED' ) {
        exit 0;
    }

    croak(
        "Something went wrong!\nFlow Summary: ",
        Dumper $flow_result->{'executionSummary'}
    );
}

sub run_flow {
    my $ua   = shift;
    my $host = shift;
    my $fid  = shift;
    my $in   = shift;
    my $response;
    my $url;
    my $flow_input;
    my $r;
    my %post_data;
    my $run_name;

    $url = 'https://' . $host . '/oo/rest/v1/flows/' . $fid;

    #check if flow exists
    $r = $ua->get( $url, 'User-Agent' => 'Mozilla/4.0 (compatible; MSIE 7.0)' );

    if ( !$r->is_success ) {
        croak( 'ERROR: ' . $url . ' ' . $r->message() );
    }

    $run_name = decode_json( $r->content )->{'name'};

    # check for mandatory flow inputs
    $url = 'https://' . $host . '/oo/rest/v1/flows/' . $fid . '/inputs';

    $r = $ua->get( $url, 'User-Agent' => 'Mozilla/4.0 (compatible; MSIE 7.0)' );

    if ( !$r->is_success ) {
        croak( 'ERROR: ' . $url . ' ' . $r->message() );
    }

    #print Dumper $r->content;
    if ( $r->content ) {
        $flow_input = from_json( $r->content );
    }

    #print Dumper $flow_input;

    foreach ( @{$flow_input} ) {
        if ( $_->{'mandatory'}
            && !exists( $in->{ $_->{'name'} } ) )
        {
            croak( 'ERROR: Missing required input ' . $_->{'name'} );
        }
        else {
            next;
        }
    }

    %post_data = (
        'uuid'     => $fid,
        'runName'  => $run_name,
        'logLevel' => 'DEBUG',
    );

    if ($in) {
        $post_data{'inputs'} = $in;
    }

    my $json_post = encode_json( \%post_data );

    #print Dumper $json_post;

    #run the flow
    $url = 'https://' . $host . '/oo/rest/v1/executions';

    #construct post request with json body
    my $req = HTTP::Request->new( 'POST', $url );
    $req->content_type('application/json');
    $req->content($json_post);

    $r = $ua->request($req);

    #print Dumper $r;

    if ( !$r->is_success ) {
        croak 'ERROR: ' . $url . ' ' . $r->message();
    }

    $response = decode_json( $r->content );
    if ( $response->{'errorCode'} eq "NO_ERROR" ) {
        return $response->{'executionId'};
    }
    else {
        croak( $r->message );
    }

    return;
}

sub track_flow {    
    my $ua   = shift;
    my $host = shift;
    my $id   = shift;
    my $sec  = shift;
    my $pollsec = shift;

    my $response;
    my $url = 'https://' . $host . '/oo/rest/v1/executions/' . $id . '/summary';
    my $i   = 0;
    my $j   = ceil( $sec / $pollsec );
    my $r;

    for ( $i = 0 ; $i < $j ; $i++ ) {

        $r = $ua->get( $url,
            'User-Agent' => 'Mozilla/4.0 (compatible; MSIE 7.0)' );

        if ( !$r->is_success ) {
            croak 'ERROR: ' . $url . ' ' . $r->message();
        }

        if ( $r->content ) {
            $response = decode_json( $r->content );
        }

        if ( $response && $response->[0]->{'status'} =~ /RUNNING/g ) {
            sleep $pollsec;
        }
        else {
            return $response->[0]->{'resultStatusType'};
        }

    }

    return;
}

sub collect_result {
    my $ua   = shift;
    my $host = shift;
    my $id   = shift;
    my $response;
    my $url =
      'https://' . $host . '/oo/rest/v1/executions/' . $id . '/execution-log';
    my $r;

    $r = $ua->get($url);

    if ( !$r->is_success ) {
        croak 'ERROR: ' . $url . ' ' . $r->message();
    }

    if ( $r->content ) {
        $response = decode_json( $r->content );
        return $response;
    }

    return;

}

main();

__END__

=head1 NAME

flowinvoke.pl -- Run HP OO 10 flow from the command line

=head1 SYNOPSIS

flowinvoke.pl [options]

 Options:

    --help             This help message
    --host=ip:port     The hostname of OO server. Should include port also (default: localhost:8443)
    --user             username (default: admin)
    --pass="secret"    password for the user (default: admin) 
    --uuid=UUID        The UUID of the flow you want to run
    --input            Key=value pair of inputs for the flow 
                       (repeat for more inputs e.g. --input key1=value1 --input key2=value2)
    --encode           Encodes username and password for use with OO api. Should be in form of username:password string.
    --credentials      Use the encoded output of --encode to connect to OO instead of using the --user and --password option.                   
    --timeout          The time to wait for flow completion in seconds (Default: 3600 - 1hour)
    --hearhbeat        Operation Orchestration polling interval (Default: 120 secs)
    --async            Run the flow in asynchronous mode (don't wait for the end result Default: synchronous)
    --verbose          By default only the flow Result is printed. Verbose will print json object that contains
                       also the flow execution summary and all bound inputs   

=head1 DESCRIPTION

This script is a functional replacement of the JRSFlowInvoke utility, that was shiped with the OO 9.x Studio. 
It allows one to execute OO flow from command line and waits for it to finish providing back the result. If used with async 
option it runs the flow and exits immediately without waiting for the end result.

=cut
