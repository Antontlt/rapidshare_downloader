#!/usr/bin/perl

use strict;
use warnings;

use WWW::Mechanize;
use Getopt::Long;
use Pod::Usage;
use File::Slurp;

# http://relf.livejournal.com/69652.html
#print("RapidShare.COM downloader 4.0 (c) 2005,09 by RElf\n");

my $tries   = 20;       # maximum number of tries per file
my $minsize = 20000;    # files of smaller size considered "bad"

my $fake_agent = "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)";

# wget executable name
my $wget = "wget";
$wget .= " -U \"$fake_agent\"";

my $mech = WWW::Mechanize->new(agent => $fake_agent);

$| = 1;

my %params;
GetOptions(
    'proxy|p=s' => \$params{proxy},
    'input|i=s' => \$params{input_file},
    'parse|r=s' => \$params{input_url},
    'help|h|?' => \$params{help},
) or pod2usage(2);

pod2usage(-exitstatus => 0, -verbose => 2) if $params{help};

if ($params{proxy}) {
    $wget .= " -e http_proxy=$params{proxy} --proxy";
}

my $all;

if ($params{input_url}) {
    $mech->get($params{input_url});
    if ($mech->success) {
        $all = $mech->content;
    } else {
        warn "Can't get $params{input_url}\n";
        exit(1);
    }
}

if ($params{input_file}) {
    $all = read_file($params{input_file});
}

$all .= join(' ', @ARGV);

=head1 NAME

=head1 SYNOPSIS

Usage: rapidshare_downloader.pl [-p <proxy>] {-i <file> | -r <url>} [<url> [<url> ...]]

=cut

my @failed;
while ($all =~ m!(http://(www.)?rapidshare\.com/files/.*?)(["\n\s]|$)!gs) {
    my $url = $1;
    if (hardGet($url)) { push(@failed, $url); }
}
while ($all =~ m!(http://(www.)?depositfiles\.com/files/.*?)(["\n\s]|$)!gs) {
    my $url = $1;
    if (hardGet($url)) { push(@failed, $url); }
}
print("FAILED URLS: ", scalar(@failed), "\n", join("\n", @failed));

sub verb_sleep {
    my $mins = shift;
    for(my $m =$mins; $m > 0; $m--) {
        print("\rWaiting $m minutes... ");
        sleep(60);
    }
    print("\rWaiting $mins minutes completed!\n");
}

sub hardGet {
    my $url = shift;
    my $t = 1;
    my $rc;

    do {
        print("Try:", $t, ": ", $url, "\n");
        $rc = rapidGet($url);
        print("RETURN: ", $rc, "\n");
        if ($rc == 50003) {
            if (/try again in about (\d+) minutes/) {
                verb_sleep($1);
                $rc = 1;
                $t--;
            } elsif (/try again later/) {
                print("Suggested to try again.\n");
                $rc = 1;
            } elsif (/Your IP-address (.*) is already downloading/) {
                print("Your IP $1 is already downloading something.\n");
                $rc = 1;
            } else {
                print("Please check manually!\n");
            }
        }

        if ($rc >= 50000) {
            print("CRITICAL ERROR. Giving up.\n");
            return $rc;
        } else {
            print("Cooling down...\n");
            sleep 60;
        }
    } while ($t++ < $tries && $rc);

    if ($rc) { print("FAILED:", $rc, ": ", $url, "\n"); }
    return $rc;
}

sub depositGet {
    my $url = shift;
    my $rc = 0;

    $mech->get($url);
    $mech->submit_form(
       form_number => 2,
    );

    if ($mech->content =~ /<form action="([^"]*)" method="get" onSubmit="download_started\(\);show_begin_popup\(0\);"/) {
        print "Getting $1\n";
        $_ = `$wget -c --referer=$url $1`;
    } elsif ($mech->content =~ /Attention! You used up your limit for file downloading! Please try in[\s\r\n]+(\d+) minute/) {
        verb_sleep($1);
    } elsif ($mech->content =~ /We are sorry, but all downloading slots for your country are busy/) {
        print "Slots busy\n";
        verb_sleep(1);
    } else {
        print "Url not found\n";
    }
}

sub rapidGet {
    my $url = shift;
    my $rc = 0;

    if ($url =~ /depositfiles\.com/) {
        return depositGet($url);
    }

    # parse url
    if ($url !~ /rapidshare\.com(.*)$/) { return 50000; }
    my $location = $1;
    if ($location !~ /\/([^\/]*?)(.html)?$/) { return 50001; }
    my $filename = $1;

    # click [Free] button and process the second page
    $_ = `$wget $url -O -`;
    if (
        !m/ action=\"([^\"]*)\" method=\"post\"\>\s*\<input type=\"hidden\" name=\"([^\"]*)\" value=\"Free\" \/\>/s
      )
    {
        return 50002;
    }

    $_ = `$wget $1 -O - --post-data="$2=Free" --referer=$url`;
    if ($?) { return 10000 + $?; }

    if (!/\<form name=\"dlf\" action=\"([^\"]*)\" method=\"post\"\>/) {
        return 50003;
    }
    my $link = $1;

    if (/var c=(\d+);/) {
        print("Waiting $1 seconds...\n");
        sleep($1);
    }

    `$wget -O "$filename" --referer=http://rapidshare.com/ $link`;
    if ($?) {
        $rc = 30000 + $?;
    } else {
        my $size = -s $filename;
        if ($size < $minsize) { $rc = 40000; }
    }

    return $rc;
}

