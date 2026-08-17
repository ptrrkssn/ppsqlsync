# Peter's Perl Library
#
# Version 2.4
#
# Author: Peter Eriksson <peter.x.eriksson@liu.se>
#

package PPL;

use Exporter qw(import);
our @EXPORT = qw(ppl_set_debug ppl_set_no sql_connect sql_disconnect sql_error sql sql_1h sql_1v sql_select sql_select_1h sql_select_1v sql_insert sql_update sql_qi sql_delete sec2datetime str2datetime sec2human str2sec ps str2bool int2size size2int wild2like plural trim h_str h_th h_td h_a_start h_a_end h_a_str dns_lookup dirname h_equal dns_rr2autofs in_list hash_equal rest_connect rest_foreach h_header h_footer);

use strict;
use warnings;

use DBI;
use POSIX qw(strftime);
use Net::DNS;

use REST::Client;
use XML::Simple;

my $f_debug = 0;
my $f_no = 0;

my $debug_fh = *STDERR;


# --- INTERNAL FUNCTIONS --------------------------------------------------

sub _fetchrows_ah {
    my ( $rs ) = @_;
    my @res;

    while (my $row = $rs->fetchrow_hashref()) {
	push @res, $row;
    }

    return @res;
}


sub _fetchrows_aa {
    my ( $rs ) = @_;
    my @res;

    while (my $row = $rs->fetchrow_arrayref()) {
	push @res, $row;
    }

    return @res;
}

sub _print_args {
    my @res;

    foreach my $v (@_) {
	if (!defined $v) {
	    push @res, 'NULL';
	} elsif ($v =~ /^[\d\.]+$/) {
	    push @res, $v;
	} else {
	    push @res, "\"$v\"";
	}
    }

    return join(', ', @res);
}

sub _sql {
    my $db = shift;
    my $statement = shift;
    my $rc;

    print $debug_fh "<!-- SQL(\"".ps($statement)."\", "._print_args(@_).") -->\n" if $f_debug;

    if (!$f_no || $statement =~ /^SELECT/i) {
        my $rs = $db->prepare($statement);
        $rc = $rs->execute(@_) if $rs;
        return ($rc, $rs);
    }
}


# --- PUBLIC DEBUG FUNCTIONS ----------------------------------------------------------------------


sub ppl_set_debug {
    $f_debug = shift;
    my $fh = shift;

    $debug_fh = $fh if defined $fh;
}

sub ppl_set_no {
    $f_no = shift;
}


# --- PUBLIC SQL FUNCTIONS ----------------------------------------------------------------------


sub sql_disconnect {
    my $db = shift;

    $db->disconnect;
}


sub sql_qi {
    my $db = shift;
    my $v = shift;

    return unless $db;
    return unless $v;

    return $db->quote_identifier($v);
}

sub sql_connect {
    my $db_type;
    my $db_user;
    my $db_pass;
    my $db_host;
    my $db_name;

    if (2 == @_) {
        my $db_uri = shift;
        $db_pass = shift;

        # mysql://user@host/name
        if ($db_uri =~ /^([a-z0-9]+):\/\/([a-z0-9_-]+)@([a-z0-9\._-]+)\/([a-z0-9_]+)$/i) {
            $db_type = $1;
            $db_user = $2;
            $db_host = $3;
            $db_name = $4;
        } else {
            # Invalid URI
            return;
        }
    } elsif (5 == @_) {
        $db_type = shift;
        $db_user = shift;
        $db_pass = shift;
        $db_host = shift;
        $db_name = shift;
    } else {
        return;
    }

    my $attrs = { AutoCommit => 1, RaiseError => 0, PrintError => 0 };
    $attrs->{mysql_enable_utf8} = 1 if $db_type && $db_type eq 'mysql';

    return DBI->connect("DBI:${db_type}:host=${db_host};database=${db_name}", $db_user, $db_pass, $attrs);
}

sub sql_error {
    return $DBI::errstr;
}

sub sql {
    my $db = shift;
    my $statement = shift;

    my ($rc, $rs) = _sql($db, $statement, @_);

    return $rc if $statement =~ /^UPDATE/i || $statement =~ /^DELETE/i || $statement =~ /^INSERT/i;
    return unless defined $rs;
    return _fetchrows_ah($rs);
}


sub sql_1h {
    my $db = shift;
    my $statement = shift;

    my ($rc, $rs) = _sql($db, $statement, @_);

    return unless defined $rc;

    # Get result row
    my $row = $rs->fetchrow_hashref();

    return unless $row;

    # Make sure a single row is returned
    return if $rs->fetchrow_hashref();

    return $row;
}


sub sql_1v {
    my $db = shift;
    my $statement = shift;

    my ($rc, $rs) = _sql($db, $statement, @_);

    return unless defined $rc;

    # Get result row
    my $row = $rs->fetchrow_arrayref();

    return unless $row;

    # Make sure a single row is returned
    return if $rs->fetchrow_arrayref();

    # Make sure a single column is returned
    return unless 1 == @$row;

    return @{$row}[0];
}



sub sql_hash2q {
    my $db = shift;
    my $h = shift;

    my $xs = '';
    my $nc = 0;

    for my $n (keys %$h) {
	$xs .= " AND " if $nc > 0;
	$xs .= $db->quote_identifier($n)."=".$db->quote($h->{$n});
	$nc++;
    }

    return $xs;
}


sub sql_select {
    my $db = shift;
    my $table = $db->quote_identifier(shift); # XXX: FIXME: Funkar inte med Postgres...
    my $extra = shift;
    my $order = shift;

    my $xs = '';
    if (defined $extra) {
	if (ref $extra eq 'HASH') {
	    $xs = ' WHERE '.sql_hash2q($db, $extra);
	} else {
	    if ($extra =~ /^\s*(ORDER\s+BY|WHERE)\s+(.*)$/i) {
		$xs = " $1 $2";
	    } else {
		$xs = " WHERE ${extra}";
	    }
	}
    }
    if (defined $order) {
	$xs .= " ".$order;
    }

    return sql($db, "SELECT * FROM ${table}${xs}", @_);
}

sub sql_select_1h {
    my $db = shift;
    my $table = $db->quote_identifier(shift);
    my $extra = shift;
    my $order = shift;

    my $xs = '';
    if (defined $extra) {
	if (ref $extra eq 'HASH') {
	    $xs = ' WHERE '.sql_hash2q($db, $extra);
	} else {
	    if ($extra =~ /^\s*(ORDER\s+BY|WHERE)\s+(.*)$/i) {
		$xs = " $1 $2";
	    } else {
		$xs = " WHERE ${extra}";
	    }
	}
    }
    if (defined $order) {
        $xs .= " ".$order;
    }

    return sql_1h($db, "SELECT * FROM ${table}${xs}", @_);
}

sub sql_select_1v {
    my $db = shift;
    my $table = shift;
    my $key = shift;

    my $res = sql_select_1h($db, $table, @_);
    return unless defined $res;
    return $res->{$key};
}

sub sql_insert {
    my $db = shift;
    my $table = $db->quote_identifier(shift);
    my $h = shift;

    my @nlist;
    my @qlist;
    my @vlist;
    foreach my $k (keys %$h) {
        push @nlist, $db->quote_identifier($k);
        push @qlist, '?';
        push @vlist, $h->{$k};
    }

    return sql($db, "INSERT INTO ${table} (".join(',', @nlist).") VALUES (".join(',', @qlist).")", @vlist);
}


sub sql_update {
    my $db = shift;
    my $table = $db->quote_identifier(shift);
    my $h = shift;
    my $extra = shift;

    my $xs = '';
    if ($extra) {
	if (ref $extra eq 'HASH') {
	    $xs = ' WHERE '.sql_hash2q($db, $extra);
	} else {
	    if ($extra =~ /^\s*(WHERE)\s+(.*)$/i) {
		$xs = " $1 $2";
	    } else {
		$xs = " WHERE ${extra}";
	    }
	}
    }

    # Failsafe - never update full table
    return unless $xs;

    my @nlist;
    my @vlist;
    foreach my $k (keys %$h) {
        push @nlist, $db->quote_identifier($k).'=?';
        push @vlist, $h->{$k};
    }

    return sql($db, "UPDATE ${table} SET ".join(',', @nlist).$xs, @vlist, @_);
}

sub sql_delete {
    my $db = shift;
    my $table = $db->quote_identifier(shift);
    my $extra = shift;

    my $xs = '';
    if ($extra) {
	if (ref $extra eq 'HASH') {
	    $xs = ' WHERE '.sql_hash2q($db, $extra);
	} else {
	    if ($extra =~ /^\s*(WHERE)\s+(.*)$/i) {
		$xs = " $1 $2";
	    } else {
		$xs = " WHERE ${extra}";
	    }
	}
    }

    # Failsafe - never delete full table
    return unless $xs;

    return sql($db, "DELETE FROM ${table}${xs}", @_);
}

# ----------------------------------------------------------------------

sub sec2datetime {
    my ($sec) = @_;

    return strftime("%Y-%m-%d %H:%M:%S", localtime($sec));
}

sub str2datetime {
    my ($s) = @_;

    return $s                   if $s =~ /^\d+-\d+-\d+\s+\d+:\d+:\d+$/;
    return $s.":00"             if $s =~ /^\d+-\d+-\d+\s+\d+:\d+$/;
    return $s." 00:00:00"       if $s =~ /^\d+-\d+-\d+$/;
    return $s."-01-01 00:00:00" if $s =~ /^\d+$/;

    print $debug_fh "$0: $s: Invalid datetime\n";
    exit 1;
}

sub sec2human {
    my $s = shift;

    return "$s s" if $s < 60;

    $s /= 60;
    return sprintf("%u m", $s) if $s < 60;

    $s /= 60;
    return sprintf("%u h", $s) if $s < 48;

    $s /= 24;
    return sprintf("%u d", $s) if $s < 30;

    $s /= 7;
    return sprintf("%u w", $s);
}

sub str2sec {
    my $s = shift;

    return $1*60*60*24*365 if $s =~ /^(\d+)\s*y$/i;
    return $1*60*60*24*91  if $s =~ /^(\d+)\s*q$/i;
    return $1*60*60*24*7   if $s =~ /^(\d+)\s*w$/i;
    return $1*60*60*24     if $s =~ /^(\d+)\s*d$/i;
    return $1*60*60        if $s =~ /^(\d+)\s*h$/i;
    return $1*60           if $s =~ /^(\d+)\s*m$/i;
    return $1              if $s =~ /^(\d+)\s*s?$/i;
}

# ----------------------------------------------------------------------

sub ps {
    my ($s, $undef) = @_;

    $undef = "-undef-" unless defined $undef;

    return $undef unless defined $s;
    return $s;
}

sub str2bool {
    my ($str) = @_;

    return 0 unless defined $str;
    return 0 if $str eq '';

    $str = lc $str;

    return 0 if $str eq 'off';
    return 0 if $str eq 'false';
    return 0 if $str =~ /^n/;
    return 0 if $str =~ /disable.*/;

    return 1 if $str eq 'on';
    return 1 if $str eq 'true';
    return 1 if $str =~ /^y/;
    return 1 if $str =~ /^enable.*/;

    return 0+$str if $str =~ /\d+/;
    return $str;
}

sub dirname {
    my $n = $_[0];

    return $1 if $n =~ /^(.*)\//;
    return;
}

sub size2num {
    my $s = shift;

    return $1 if $s =~ /^([\d\.]+)\s*B?$/i;

    return $1*1024 if $s =~ /^([\d\.]+)\s*KiB?$/;
    return $1*1000 if $s =~ /^([\d\.]+)\s*KB?$/i;

    return $1*1024*1024 if $s =~ /^([\d\.]+)\s*MiB?$/;
    return $1*1000*1000 if $s =~ /^([\d\.]+)\s*MB?$/i;

    return $1*1024*1024*1024 if $s =~ /^([\d\.]+)\s*GiB?$/;
    return $1*1000*1000*1000 if $s =~ /^([\d\.]+)\s*GB?$/i;

    return $1*1024*1024*1024*1024 if $s =~ /^([\d\.]+)\s*TiB?$/;
    return $1*1000*1000*1000*1000 if $s =~ /^([\d\.]+)\s*TB?$/i;

    return $1*1024*1024*1024*1024*1024 if $s =~ /^([\d\.]+)\s*PiB?$/;
    return $1*1000*1000*1000*1000*1000 if $s =~ /^([\d\.]+)\s*PB?$/i;
}

sub size2int {
    my $s = shift;

    return sprintf("%.0f", size2num($s));
}

sub int2size {
    my $v = shift;
    my $f_base_1024 = shift;

    return unless defined $v;

    if ($f_base_1024) {
        return $v." " if $v < 1024.0;

        $v /= 1024.0;
        return sprintf("%.1f Ki", $v) if $v < 1024.0;

        $v /= 1024.0;
        return sprintf("%.1f Mi", $v) if $v < 1024.0;

        $v /= 1024.0;
        return sprintf("%.1f Gi", $v) if $v < 1024.0;

        $v /= 1024.0;
        return sprintf("%.1f Ti", $v);
    } else {
        return $v." " if $v < 1000.0;

        $v /= 1000.0;
        return sprintf("%.1f K", $v) if $v < 1000.0;

        $v /= 1000.0;
        return sprintf("%.1f M", $v) if $v < 1000.0;

        $v /= 1000.0;
        return sprintf("%.1f G", $v) if $v < 1000.0;

        $v /= 1000.0;
        return sprintf("%.1f T", $v);
    }
}

sub wild2like {
    my ($text) = @_;

    return unless defined $text;

    my %map = (
	'%' => '\\%',
	'_' => '\\_',
	'*' => '%',
	'?' => '_',
	);

    my $chars = join '', keys %map;
    $text =~ s/([$chars])/$map{$1}/g;
    return $text;
}


sub plural {
    my ($subject, $n) = @_;

    return $subject if defined $n && $n eq 1;

    if ($subject =~ /(s|h)$/) {
	return $subject."es" if defined $n;
	return $subject."(es)";
    }

    return $subject."s" if defined $n;
    return $subject."(s)";
}

sub trim {
    my $s = shift;

    return unless defined $s;

    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s =~ s/\s\s+/ /g;

    return $s;
}

# --- HTML FORMATTING FUNCTIONS ----------------------------------------------------------------------

sub _h_eval_string {
    my $s = shift;
    my $v = shift;

    while ($s =~ /^(.*)\$\{([A-Z]+)\}(.*)$/) {
        my ($a, $b, $c) = ($1, lc $2, $3);

        if (defined $v->{$b}) {
            $s = "${a}$v->{$b}${c}\n";
        } else {
            $s = "${a}${c}\n";
        }
    }

    return $s;
}

sub h_header {
    my $vars = shift;
    my $res = "";


    my @headers;
    push @headers, $vars->{header} if defined $vars && defined $vars->{header};
    push @headers, 'header.html';
    push @headers, '/var/www/html/header.html';

    my $fh;
    foreach my $path (@headers) {
        if (open($fh, "<", $path)) {
            my $n = 0;
            while (<$fh>) {
                $n++;
                if ($n == 1 && !($_ =~ /^Content-Type:\s/i)) {
                    $res .= "Content-Type: text/html; charset=utf-8\n\n";
                }

                $res .= _h_eval_string($_, $vars);
            }
            close($fh);
            return $res;
        }
    }

    $res .= "Content-Type: text/html; charset=utf-8\n\n";
    $res .= "<html><head>";
    $res .= "<title>$vars->{title}</title>" if defined $vars && defined $vars->{title};
    $res .= "</head><body>\n";
    return $res;
}

sub h_footer {
    my $vars = shift;
    my $res = "";

    my @footers;
    push @footers, $vars->{footer} if defined $vars && defined $vars->{footer};
    push @footers, 'footer.html';
    push @footers, '/var/www/html/footer.html';

    my $fh;
    foreach my $path (@footers) {
        if (open($fh, "<", $path)) {
            while (<$fh>) {
                $res .= _h_eval_string($_, $vars);
            }
            close($fh);
            return $res;
        }
    }

    return "</body></html>\n";
}


sub h_str {
    my ($str, $cgi) = @_;

    return '' unless defined $str;

    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;

    if ($cgi) {
	$str =~ s/\ /&#32;/g;
	$str =~ s/\+/&#43;/g;
#	$str =~ s/\;/&#59;/g;
	$str =~ s/\'/&#39;/g;
    }

    $str =~ s/\n/<br>/g;
    return $str;
}

sub h_thtd {
    my $tdth = shift;
    my $v = shift;
    my $opts = shift;

    my $ts = '';
    $ts = ' data-toggle="tooltip" title="'.h_str($opts->{tooltip}).'"' if $opts && $opts->{tooltip};

    my $hs1 = '';
    my $hs2 = '';
    if ($opts && $opts->{href}) {
	$hs1 = '<a href="'.h_str($opts->{href},1).'"';
	$hs1 .= ' target=\"'.$opts->{target}.'\"' if $opts->{target};
	$hs1 .= '>';
	$hs2 = '</a>';
    }

    my $cs = '';
    $cs = ' class="'.h_str($opts->{class}).'"' if $opts && $opts->{class};

    my $ss = '';
    $ss = ' style="'.h_str($opts->{style}).'"' if $opts && $opts->{style};

    my $is = '';
    $is = ' id="'.h_str($opts->{id}).'"' if $opts && $opts->{id};

    if ($opts && $opts->{input}) {
	my $iopts = $opts->{input};

	my $is = "";
	foreach my $n (keys %$iopts) {
	    if (defined $iopts->{$n}) {
		$is .= " ".$n."=\"".h_str($iopts->{$n})."\"";
	    } else {
		$is .= " ".$n;
	    }
	}
	return "<${tdth}${cs}${ss}${is}${ts}>${hs1}<input${is}  value=\"".h_str($v)."\">${hs2}</${tdth}>\n";
    }

    return "<${tdth}${cs}${ss}${is}${ts}>${hs1}".h_str($v)."${hs2}</${tdth}>\n";
}

sub h_th {
    return h_thtd('th', @_);
}

sub h_td {
    return h_thtd('td', @_);
}

sub h_a_start {
    my $h = shift;
    my $s = '<a';
    for my $n (keys %$h) {
	next unless $h->{$n};
	$s .= ' '.h_str($n).'="'.h_str($h->{$n}).'"';
    }
    $s .= '>';
    return $s;
}

sub h_a_end {
    return '</a>';
}

sub h_a_str {
    my $s = shift;
    my $h = shift;

    return h_a_start($h).h_str($s).h_a_end();
}

my $_dns_res;
sub dns_lookup {
    my ( $name, $q ) = @_;
    my @r;

    $_dns_res = Net::DNS::Resolver->new unless $_dns_res;
    return unless $_dns_res;

    my $dnsq = $_dns_res->search($name, $q);
    return unless $dnsq;

    foreach my $rr ($dnsq->answer) {
	if ($rr->type eq $q) {
	    if ($q eq 'PTR') {
		push @r, $rr->ptrdname;
	    } else {
		push @r, $rr->address;
	    }
	}
    }

    return @r;
}


sub _scmp {
    my ($a, $b) = @_;

    return -1 if !defined $a &&  defined $b;
    return 1 if  defined $a && !defined $b;
    return 0 if !defined $a && !defined $b;
    return $a cmp $b;
}

sub scmp {
    my ($a, $b) = @_;
    my $r = _scmp($a, $b);
    return $r;
}

sub match {
    my $a = shift;

    foreach my $b (@_) {
        next if  defined $a && !defined $b;
        next if !defined $a &&  defined $b;
        return 1 if !defined $a && !defined $b;
        return 1 if $a cmp $b;
    }

    return 0;
}

sub h_equal {
    my $o = shift;
    my $n = shift;
    my @ignore = @_;

    my @ok = keys %$o;
    my @nk = keys %$n;

    my %seen;
    @seen{@ok} = ();
    my @keys = (@ok, grep{!exists $seen{$_}} @nk);

    foreach my $k (@keys) {
	next if 0 < @ignore && match($k, @ignore);
	return 0 if scmp($o->{$k}, $n->{$k});
    }

    return 1;
}


#
# Convert a DNS RR (Resource Record) TXT record
# formatted as Hesiod, AMD or Sun style into a
# hash usable for Automount data. Keys:
#
# type (nfs)
# name (peter86)
# server (filur01.it.liu.se)
# path (/staff/peter86)
# options (ro)
#
sub dns_rr2autofs {
    my $rr = shift;
    my $res;

    my $name = $rr->name;
    my @data = $rr->txtdata;

    my $rdata = join(' ', @data);

    $name = $1 if $name =~ /^([^\.]+)\./;

    my ($type, $opts, $serv, $path);

    if ($rdata =~ /^NFS\s+(.+)\s+(.+)\s+(.+)\s(.+)$/) {
	$type = 'nfs';
	$opts = $3 if $3 ne '-';
	$serv = $2;
	$path = $1;
    } elsif ($rdata =~ /^[a-z]+:=([^\;])/) {
	my @av = split(/;/, $rdata);
	my $sublink;

	foreach my $a (@av) {
	    if ($a =~ /^([a-z]+):=(.+)$/) {
		my ($key, $val) = ($1, $2);
		if ($key eq 'type') {
		    $type = $val;
		} elsif ($key eq 'opts') {
		    $opts = $val;
		} elsif ($key eq 'rhost') {
		    $serv = $val;
		} elsif ($key eq 'rfs') {
		    $path = $val;
		} elsif ($key eq 'sublink') {
		    $sublink = $val;
		}
	    }
	}
	$path .= "/${sublink}" if $sublink;
    } elsif ($rdata =~ /^-(.+)\s+([^:]+):(\/.+)$/) {
	$type = 'nfs';
	$serv = $2;
	$opts = $1;
	$path = $3;
    } elsif ($rdata =~ /^([^:]+):(\/.+)$/) {
	$type = 'nfs';
	$serv = $1;
	$path = $2;
    } else {
        return;
    }

    $res->{type} = $type;
    $res->{name} = $name;
    $res->{server} = $serv;
    $res->{path} = $path;
    $res->{options} = $opts;

    return $res;
}

sub in_list {
    my $v = shift;

    foreach (@_) {
	return 1 if ($v cmp $_) == 0;
    }

    return 0;
}

sub hash_equal {
    my $o = shift;
    my $n = shift;
    my $c = shift;

    my @ignore;
    if (ref $c eq 'HASH') {
	@ignore = @{$c->{ignore}} if defined $c->{ignore};
    }

    my @ok = keys %$o;
    my @nk = keys %$n;

    my %seen;
    @seen{@ok} = ();
    my @keys = (@ok, grep{!exists $seen{$_}} @nk);

    foreach my $k (@keys) {
	next if in_list($k, @ignore);
	if (scmp($o->{$k}, $n->{$k})) {
#	    print "$k: ".ps($o->{$k})." vs ".ps($n->{$k})."\n";
	    return 0;
	}
    }

    return 1;
}

# ----------------------------------------------------------------------

sub rest_connect {
    my $uri = shift;
    my $pass = shift;

    my ($prot, $user, $data);

    my $rest = REST::Client->new();

    if ($pass) {
        if ($uri =~ /^([a-z]+):\/\/([a-z0-9]+)@(.*)$/) {
            $prot = $1;
            $user = $2;
            $data = $3;

            my $x = "${prot}"."://"."${user}".":"."${pass}"."@"."${data}";
            $rest->setHost($x);
            return $rest;
        }
    } else {
        $rest->setHost($uri);
        return $rest;
    }
}

sub rest_foreach {
    my $rest = shift;
    my $url = shift;
    my $handler = shift;
    my $data = shift;

    my $start;

    do {
        my $r = $rest->GET($url."?.full=true".(defined $start ? "\&.firstResult=$start" : ""));
        return unless defined $r;

	my $rc = $r->responseCode();
	return $rc unless $rc >= 200 && $rc <= 299;

        my $rct = $r->responseContent();
        return unless defined $rct;

        my $h = XMLin($rct, ForceArray => 0);
        return unless defined $h;

        return 0 unless defined $h->{last};
        $start = $h->{last}+1;

	foreach my $e (@{$h->{entity}}) {
            $rc = $handler->($e->{type}, $e->{$e->{dtoType}}, $data);
            return $rc unless $rc == 0;
        }
    } while (1);

    return 0;
}

1;
