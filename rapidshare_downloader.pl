#!/usr/bin/perl

use strict;
use warnings;

use WWW::Mechanize;

# http://relf.livejournal.com/69652.html
#print("RapidShare.COM downloader 4.0 (c) 2005,09 by RElf\n");

my $tries   = 20;       # maximum number of tries per file
my $minsize = 20000;    # files of smaller size considered "bad"

my $fake_agent = "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)";

# wget executable name
my $wget = "wget";

# wget options: set up proxy or fake agent or both or whatever...
#$wget .= " -e http_proxy=192.168.0.1:80 --proxy";
$wget .= " -U \"$fake_agent\"";

my $mech = WWW::Mechanize->new(agent => $fake_agent);

$| = 1;

if ($#ARGV < 0) {
    print("Usage: rapidl_com.pl [-p <proxy>] {<url> | -i <file> | -r <url>}\n");
    exit;
}

my $all;
for (my $i = 0; $i <= $#ARGV; ++$i) {
    if ($ARGV[$i] eq "-p") {
        $wget .= " -e http_proxy=$ARGV[++$i] --proxy";
    } elsif ($ARGV[$i] eq "-r") {
        $all = `$wget -O - $ARGV[++$i]`;
    } elsif ($ARGV[$i] eq "-i") {
        my $old = $/;
        open(UL, $ARGV[++$i]) or die("Cannot open URL list!");
        $/   = undef;
        $all = <UL>;
        close(UL);
        $/ = $old;
    } elsif ($i == $#ARGV) {
        $all = $ARGV[$i];
    } else {
        print("Unrecognized option.\n");
        exit;
    }
}

my @failed;
while ($all =~ m!(http://(www.)?(rapidshare|depositfiles)\.com/files/.*?)(["\n\s]|$)!gs) {
    my $url = $1;
    if (hardGet($url)) { push(@failed, $url); }
    print($url, "\n");
}
print("FAILED URLS: ", scalar(@failed), "\n", join("\n", @failed));


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
                for (my $m = $1; $m; $m--) {
                    print("\rWaiting $m minutes... ");
                    sleep(60);
                }
                print("\rWaiting $1 minutes completed!\n");
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
        print "Have to sleep $1 minutes\n";
        sleep(60 * $1);
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

