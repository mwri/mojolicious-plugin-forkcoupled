#!/usr/bin/perl


use strict;
use warnings;

use ExtUtils::MakeMaker;


WriteMakefile(
	'NAME'         => 'Mojolicious::Plugin::ForkCoupled',
	'VERSION_FROM' => 'lib/Mojolicious/Plugin/ForkCoupled.pm',
	'TESTS'        => 't',
);
