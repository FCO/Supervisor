use JSON::RPC::Client;
use JSON::RPC::Server;

unit class Supervisor;

class Process { ... }

class Node {
  has Str  $.name                  = "main";
  has Str  $.host                  = "localhost";
  has UInt $.port where * <= 65535 = 1234;
  has      $!conn;

  my %by-name;
  my %by-port;

  method TWEAK(|) {
    %by-name{ $!name } = self;
    %by-port{ $!port } = self if $!host eq "localhost";
  }

  method COERCE-FROM(Str:D $str) {
    do if $str ~~ /[ $<name>=\w+ \s+ ]? $<host>=<[\w.]>+ [":" $<port>=\d+]? / {
      self.new: |(:name(.Str) with $<name>), |(:host(.Str) with $<host>), |(:port(.Int) with $<port>)
    } else {
      fail "String '$str' not recognised"
    }
  }

  multi method CALL-ME(Str $name) {
    fail "Not found Node with name '$name'" without %by-name{ $name };
    %by-name{ $name }
  }

  method Str { "{ $!name } { $!host }:{ $!port }" }

  method WHICH {
    ValueObjAt.new: "{ ::?CLASS.^name }|{ self.Str }"
  }

  method connect {
    $!conn = JSON::RPC::Client.new( url => "http://{ $!host }:{ $!port }" )
  }

  method spawn(|c) {
    my $process = $!conn.spawn: |c;
    Process.COERCE-FROM: $process
  }

  method send(|c) {
    start ($!conn //= $.connect).receive: |c
  }

  method run-server($actor) {
    note "Starting server on port $!port";
    JSON::RPC::Server.new( application => $actor ).run( :$!port, :!debug )
  }
}

class Process {
  has Node $.node .= new;
  has UInt $.pid = 0;

  method COERCE-FROM(Str:D $str) {
    do if $str ~~ /$<node>=[ [ \w+ \s+ ]? <[\w.]>+ [":" \d+]? \s+]? $<pid>=\d+/ {
      self.new: |(:node(Node.COERCE-FROM: .Str) with $<node>), :pid(+$<pid>)
    } else {
      fail "String '$str' not recognised"
    }
  }

  method Str { "{ $!node.Str } $!pid" }

  method send(|c) {
    $!node.send: $!pid.Int, $*SUP-PROCESS.Str, |c
  }
}

has Node        $.node handles <host port name> .= new;
has Node        @.nodes;
has Channel     %!channels;
has             $!server;
has Promise     $.running = start { $!server = $!node.run-server(self) };
has             %.spawned{ UInt };
has atomicint   $!next-pid = 1;
has             %.funcs;
has Lock::Async $!lock .= new;

method !channels { %!channels }

method BUILD(:@nodes, :$port, :%!funcs, |) {
  @!nodes = Array[Node].new: @nodes.map: { Node.COERCE-FROM: $_ } if @nodes;
  $!node .= new: :$port with $port;
}

method run-main(&block, :@nodes) {
  for @!nodes -> $node {
    $node.connect
  }
  my $PROCESS::SUP-PROCESS = Process.new: :$!node, :pid(0);
  block
}

method run-node(&block?) {
  my $PROCESS::SUP-PROCESS = Process.new: :$!node, :pid(0);
  .() with &block;
  await $*SUPERVISOR.running;
}

multi run-supervisor(&block, UInt :$port, :@nodes, :%funcs) is export {
  $PROCESS::SUPERVISOR = Supervisor.new: |(:$port with $port), |(:@nodes if @nodes), |(:%funcs if %funcs);
  $*SUPERVISOR.run-main: &block
}

multi run-supervisor(UInt :$port, :%funcs) is export {
  $PROCESS::SUPERVISOR = Supervisor.new: |(:$port with $port), |(:%funcs if %funcs);
  $*SUPERVISOR.run-node
}

method !channel-named($pid) {
  $!lock.protect: {
    %!channels{ $pid } //= Channel.new
  }
}

sub receive(&block) is export {
  my $supervisor = $*SUPERVISOR;
  my $sup-pid = $*SUP-PROCESS;
  given $supervisor!channel-named($sup-pid.pid) -> $chn {
    react whenever $chn -> [ Capture $data, Process $*from ] {
      my $*SUPERVISOR = $supervisor;
      my $*SUP-PROCESS = $sup-pid;
      CATCH {
        default {
          .note
        }
      }
      block |$data
    }
  }
}

proto spawn(|) is export {*}

multi spawn(Str $name, |c) {
  $*SUPERVISOR.spawn: $name, |c
}

multi spawn(Node $node, Str $name, |c) {
  $node.spawn: $name, |c
}

method spawn(Str $name, |c) {
  my UInt $pid = $!next-pid⚛++;
  %!spawned{ $pid } = start {
    my $*SUP-PROCESS = Process.new: :$!node, :$pid;
    CATCH {
      default {
        .note
      }
    }
    %!funcs{$name}.(|c)
  }
  Process.new(:$!node, :$pid).Str
}

method receive(UInt $pid, Str $process, |c) {
  $!lock.protect: {
    with %!channels{ $pid } {
      my $from = Process.COERCE-FROM: $process;
      .send: [ c, $from ]
    } else{
      die "Process $pid not waiting to receive messages."
    }
  }
}

=begin pod

=head1 NAME

Supervisor - blah blah blah

=head1 SYNOPSIS

=begin code :lang<raku>

use Supervisor;

=end code

=head1 DESCRIPTION

Supervisor is ...

=head1 AUTHOR

 <foliveira@gocardless.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2022 

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
