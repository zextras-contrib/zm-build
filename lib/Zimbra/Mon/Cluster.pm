#!/usr/bin/perl

package Zimbra::Cluster;

use strict;

use Zimbra::Logger;
use host;
use Zimbra::shortInfo;
use Zimbra::serviceInfo;
use SOAP::Lite;
use Zimbra::ProvTool;
use Socket;

my $statefile = "$::Basedir/state.cf";

require Exporter;

my @ISA = qw(Exporter);

my @EXPORT = qw (getClusterHosts getClusterInfo);

# TODO - MEM - put servers in host object
# TODO - MEM - read all services into hosts into cluster
# TODO - MEM - add TimeStamp to host info for caching
# TODO - MEM - add getTimeStamp call for inter-host caching

sub new {
	my ( $class, $applications, $services, $syntaxes ) = @_;

	my $self = bless {}, $class;

	$self->{Hosts}        = ();
	$self->{Applications} = $applications;
	$self->{Services}     = $services;

	$self->{Syntaxes} = $syntaxes;

	$self->{Prov} = new Zimbra::ProvTool();

	$self->readState();

	#Zimbra::Logger::Log( "debug", "Created Cluster" );
#	my $s;
#	foreach $s ( @{ $self->{Applications} } ) {
#		Zimbra::Logger::Log( "debug", "APP: $s->{name}" );
#	}

	return $self;
}

sub getClusterInfo {
	#Zimbra::Logger::Log( "debug", "Zimbra::Cluster::getClusterInfo" );
	my $self = shift;
	$self->{ShortInfo} = new Zimbra::shortInfo( $self->{LocalHost} );
	$self->setShortInfo();
	$self->{ServiceInfo} = new Zimbra::serviceInfo( $self->{LocalHost} );

	#$self->setServiceInfo();
}

sub readState {
	my $self = shift;
	my $h = `zmlocalconfig -m nokey zimbra_server_hostname`;
	chomp $h;
	my $ip = gethostbyname($h);
	if ($ip ne "") {
		$ip = inet_ntoa($ip);
	} else {
		Zimbra::Logger::Log( "err", "Can't resolve host $h" );
	}
	$self->{LocalHost} = $self->doAddHost( $h, $ip );
}

sub getHostsFromLdap {
	my $self = shift;

	Zimbra::Logger::Log( "debug", "Create host list from LDAP" );
	my $hostlist = $self->{Prov}->gas();
	$self->{Hosts}     = ();
	foreach (@$hostlist) {
		chomp;
		Zimbra::Logger::Log( "debug", "Prov found host: $_" );
		$self->addProvHost($_);
	}
}

sub writeState {
	my $self = shift;
	Zimbra::Logger::Log( "debug", "Started writing state" );
	open CF, ">$statefile" or die "Can't open $statefile: $!";
	print CF "LOCALHOST " . $self->{LocalHost}->prettyPrint() . "\n";
#	my $h;
#	foreach $h ( @{ $self->{Hosts} } ) {
#		print CF "HOST " . $h->prettyPrint() . "\n"
#		  unless ( $h == $self->{LocalHost} );
#	}
	close CF;
	Zimbra::Logger::Log( "debug", "Finished writing state" );
}

sub getClusterHosts {

	# TODO - MEM - set up some sort of taint aging for this info
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::getClusterHosts" );
	$self->readState();
	$self->getHostsFromLdap();

	#Zimbra::Logger::Log ("info",join " ", @{$self->{Hosts}});
	return @{ $self->{Hosts} };

}

sub getLocalServices {
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::getLocalServices" );
	return $self->{Services};
}

sub getLocalApplications {
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::getLocalServices" );
	return $self->{Applications};
}

sub getLocalShortInfo {
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::getLocalShortInfo" );

	my $MAX_AGE = 300;

	$self->setShortInfo();

	return $self->{ShortInfo};
}

sub getLocalServiceInfo {
	my $self = shift;

	$self->setServiceInfo();

	return $self->{ServiceInfo};
}

sub setServiceInfo {
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::setServiceInfo" );

	my $TS = time();
	$self->{ServiceInfo}->{cts} = $TS;

	$self->{ServiceInfo}->getServiceInfo();
}

sub setShortInfo {
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::setShortInfo" );

	my $TS = time();
	$self->{ShortInfo}->{cts} = $TS;

	$self->{ShortInfo}->readShortInfo();
}

sub controlLocalService {
	my $self = shift;
	my $cmd  = shift;
#	my $sn   = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::controlLocalService: $cmd $sn" );

	$self->sendFifo("$cmd");

	my $resp = $self->readFifo();
	return $resp;
}

sub openFifo {
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::openFifo" );
	open( CONTROL, "+< $::FifoPath" ) or warn("Zimbra::Cluster::openFifo Can't open $::FifoPath: $!");

	my $fh = select CONTROL;
	$| = 1;
	select $fh;
}

sub openResponseFifo {
	my $self = shift;
#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::openResponseFifo" );
	if ( open( RESPONSE, "+< $::FifoDir/$$.response" ) ) {
	}
	else {
		Zimbra::Logger::Log( "debug", "Can't open $::FifoDir/$$.response: $!" );
		sleep 4;
		if ( !( open( RESPONSE, "+< $::FifoDir/$$.response" ) ) ) {
			Zimbra::Logger::Log( "info", "Can't open $::FifoDir/$$.response: $!" );
			sleep 4;
			if ( !( open( RESPONSE, "+< $::FifoDir/$$.response" ) ) ) {
				Zimbra::Logger::Log( "err", "Can't open $::FifoDir/$$.response: $!" );
				return 0;
			}
		}
	}

	my $fh = select RESPONSE;
	$| = 1;
	select $fh;
	return 1;
}

sub sendFifo {
	my $self = shift;

	$self->openFifo();

	my $args = join " ", @_;

	#Zimbra::Logger::Log ("debug","sendFifo: $args");
	my $msg = "$$ $args";
	chomp $msg;
	Zimbra::Logger::Log( "debug", "sendFifo: $msg" );
	print CONTROL "$msg\n";
	#$self->signalMainProcess();
}

sub readFifo {
	my $self = shift;
	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::readFifo" );

	if ( $self->openResponseFifo() ) {
		my $resp = <RESPONSE>;
		chomp $resp;
		Zimbra::Logger::Log( "debug", "Zimbra::Cluster::readFifo: $resp" );
		return $resp;
	}
	Zimbra::Logger::Log( "err", "Zimbra::Cluster::readFifo failed: $!" );
	return undef;
}

sub signalMainProcess {
	my $self = shift;
#	Zimbra::Logger::Log( "debug",
#		"Zimbra::Cluster::signalMainProcess $::mainProcessPid" );

	#kill( 'USR1', $::mainProcessPid );
}

sub addHost {
	my $self     = shift;
	my $hostName = shift;
	my $hostIp   = shift;
	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::addHost $hostName $hostIp" );
	my $cmd = $::syntaxes{zimbrasyntax}{addhost};

	$self->sendFifo("$cmd $hostName $hostIp");

	sleep 3;

	my $resp = $self->readFifo();
	return $resp;
}

sub addProvHost {
	my $self = shift;
	my $hn = shift;

	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::addProvHost $hn" );
	my $info = $self->{Prov}->gs($hn);
	my $ip = gethostbyname($hn);
	if ($ip ne "") {
		$ip = inet_ntoa($ip);
	} else {
		Zimbra::Logger::Log( "err", "Can't resolve host $hn" );
	}
	$self->doAddHost($hn, $ip); 

#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::doAddHost $hn, $ip" );
	#my $H = new host( $hn, $ip, $partner, $mode );

	#push( @{ $self->{Hosts} }, $H );

	#return $H;
}

sub doAddHost {
	my $self = shift;
	my ( $hn, $ip ) = (@_);

#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::doAddHost $hn, $ip" );
	my $H = new host( $hn, $ip );

	#Zimbra::Logger::Log ("debug","Remote Host $h");
	push( @{ $self->{Hosts} }, $H );

	return $H;
}

sub propagateClusterInfo {
	my $self = shift;
	my $H;
	Zimbra::Logger::Log( "debug", "propagateClusterInfo" );
	foreach $H ( @{ $self->{Hosts} } ) {
		$self->sendClusterInfo($H);
	}
}

sub sendClusterInfo {
	my $self = shift;
	my $H    = shift;
	if ( $H == $self->{LocalHost} ) { return 0; }
	my $hn = $H->{name};
	my $ip = $H->{ip};
	Zimbra::Logger::Log( "debug", "sendClusterInfo: $hn ($ip)" );

	eval {
		my $resp =
		  SOAP::Lite->proxy("http://${ip}:$::controlport/", timeout => 10)
		  ->uri("http://${ip}:$::controlport/Zimbra::Admin")
		  ->updateClusterInfoRequest( $self->{LocalHost}, $self->{Hosts} );
	
		if (!defined $resp->result()) {
			Zimbra::Logger::Log("err", "Error contacting ${ip} ($hn): No response from server: ".$resp->faultstring);
		}
	};
	if ($@) {
		Zimbra::Logger::Log("err", "Error contacting ${ip} ($hn): $@");
	}
}

sub removeHost {
	my $self     = shift;
	my $hostName = shift;
	my $hostIp   = shift;
	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::remove $hostName $hostIp" );
	my $cmd = $::syntaxes{zimbrasyntax}{removehost};
	$self->sendFifo("$cmd $hostName $hostIp");

	sleep 3;

	my $resp = $self->readFifo();
	return $resp;
}

sub doRemoveHost {
	my $self = shift;
	my ( $hn, $ip ) = (@_);

#	Zimbra::Logger::Log( "debug", "Zimbra::Cluster::doRemoveHost $hn, $ip" );
	if ( $hn eq $self->{LocalHost}->{name} || $ip eq $self->{LocalHost}->{ip} )
	{
		return "FAILURE";
	}
	my $H;
	my $i = 0;
	foreach $H ( @{ $self->{Hosts} } ) {
		if ( $H->{name} eq $hn && $H->{ip} eq $ip ) {
			splice( @{ $self->{Hosts} }, $i, 1 );
			return "SUCCESS";
		}
		$i++;
	}

	return "FAILURE";
}

sub updateClusterInfo {
	my $self = shift;
	my $sender = shift;
	my $hostlist = shift;
	my $cmd = $::syntaxes{zimbrasyntax}{updatecluster};
	
#	Zimbra::Logger::Log ("debug", "Zimbra::Cluster::updateClusterInfo");

	my $cmdstr = $cmd." ".$sender->{name}." ".$sender->{ip};
	
	foreach (@{$hostlist}) {
#		Zimbra::Logger::Log ("debug", "Zimbra::Cluster::updateClusterInfo: ".$_->{name}." ".$_->{ip});
		$cmdstr .= " ".$_->{name}." ".$_->{ip};
	}
	$self->sendFifo("$cmdstr");
}

sub getFetchRef {
	my $self = shift;
	my $filter = shift;
	
	my $cmd = $::syntaxes{zimbrasyntax}{getfetchref};
	my $f = $filter->{fetchref};
	$self->sendFifo("$cmd $f");
	
	my $resp = $self->readFifo();
	return (split ' ', $resp);
}

sub newFetchRef {
	my $self = shift;
	my $filter = shift;
	
	my $cmd = $::syntaxes{zimbrasyntax}{newfetchref};
	my $h = $filter->{hostname};
	my $st = $filter->{starttime};
	my $et = $filter->{endtime};
	$self->sendFifo("$cmd $h,$st,$et");
	
	my $resp = $self->readFifo();
	return $resp;
}

sub getHostByName {
	my $self = shift;
	my $hn   = shift;

	$self->getClusterHosts();

	foreach ( @{$self->{Hosts}} ) {
		if ( $_->{name} eq $hn ) { return $_; }
	}
	return undef;
}

sub getHostByIp {
	my $self = shift;
	my $ip   = shift;

	$self->getClusterHosts();

	foreach ( @{$self->{Hosts}} ) {
		if ( $_->{ip} eq $ip ) { return $_; }
	}
	return undef;
}



1

