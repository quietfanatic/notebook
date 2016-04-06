use v5.18;
use warnings;
use bytes;

sub compile_template {
    my ($s, $filename, $pos) = @_;
    $filename //= '<anon>';
    pos $s = $pos // 0;
    sub get_lc {
        my ($s, $pos) = @_;
        my @lines = split "\n", substr($s, 0, $pos);
        return (0+@lines, length($lines[-1]));
    }
    my @template;
    my $rx = qr/
        \{\s*(?:
            \[\s*([^\[\]{}?!<>\@\#\s]+)\s*\]
          | \?\s*([^\[\]{}?!<>\@\#\s]+)\s*\?
          | \!\s*([^\[\]{}?!<>\@\#\s]+)\s*\!
          | \<\s*([^\[\]{}?!<>\@\#\s]+)\s*\> \}
          | \@([^\@\s]+)\@ \}
          | \#([^\#]*)\# \}
          | \s*([^\[\]{}?!<>\#\s]+)\s* \}
          | \{\{ (.*?) \}\}\}
          | (\{\}) | (\}\})
        ) | (\}) | ([^{}]+) | ($)
    /xs;
    while (1) {
        my $prepos = pos $s;
        if ($s =~ /\G$rx/g) {
            my ($list, $if, $not, $html, $include, $comment, $str, $block, $lb, $rb, $end, $lit, $eos)
                = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13);
            if (defined $list) {
                (my $inner, pos $s) = compile_template($s, $filename, pos $s);
                push @template, '[', $list, $inner;
            }
            elsif (defined $if) {
                (my $inner, pos $s) = compile_template($s, $filename, pos $s);
                push @template, '?', $if, $inner;
            }
            elsif (defined $not) {
                (my $inner, pos $s) = compile_template($s, $filename, pos $s);
                push @template, '!', $not, $inner;
            }
            elsif (defined $include) {
                my $inner = compile_template(slurp($include), $include);
                push @template, @$inner;
            }
            elsif (defined $html) {
                push @template, '<', $html;
            }
            elsif (defined $comment) {
                 # It's a comment.
            }
            elsif (defined $str) {
                push @template, '=', $str;
            }
            elsif (defined $block) {
                push @template, '', $block;
            }
            elsif (defined $lb) {
                push @template, '', '{';
            }
            elsif (defined $rb) {
                push @template, '', '}';
            }
            elsif (defined $lit) {
                push @template, '', $lit;
            }
            elsif (defined $end) {
                if ($pos) {
                    return (\@template, pos $s);
                }
                else {
                    my ($l, $c) = get_lc($s, pos $s);
                    die "Unmatched } in template at $filename:$l:$c\n";
                }
            }
            elsif (defined $eos) {
                if ($pos) {
                    my ($l, $c) = get_lc($s, $pos);
                    die "Unmatched { in template at $filename:$l:$c\n";
                }
                else {
                    return \@template;
                }
            }
            else {
                die "Internal error in the template engine!\n";
            }
        }
        else {
            my ($l, $c) = get_lc($s, $prepos);
            die "Syntax error in template at $filename:$l:$c\n";
        }
    }
}

sub run_template {
    my ($action, $template, $fillings) = @_;
    ref $action eq 'CODE' or die "Action argument to run_template is not a CODE ref";
    if (ref $template eq '') {
        $template = compile_template($template);
    }
    ref $template eq 'ARRAY' or die "Invalid template given to run_template (not ARRAY ref)";
    my $i = 0;
    while ($i < @$template) {
        my $s = $template->[$i++];
        my $word = $template->[$i++];
        if ($s eq '') {
            $action->($word);
        }
        elsif ($s eq '=' && $word eq '_') {
            $action->($fillings);
        }
        elsif (ref $fillings ne 'HASH') {
            $action->("{ERROR: Fillings are not a hash ref.}");
        }
        elsif ($s eq '=') {
            my $p = $fillings->{$word};
            if (ref $p eq 'CODE') {
                $p = $p->();
            }
            if (ref $p) {
                $action->("{ERROR: non-string given to fill {$word}}");
            }
            else {
                $action->(esc_html($p // '{UNDEFINED}'));
            }
        }
        elsif ($s eq '<') {
            my $p = $fillings->{$word};
            if (ref $p eq 'CODE') {
                $p = $p->();
            }
            if (ref $p) {
                $action->("{ERROR: non-string given to fill {<$word>}}");
            }
            else {
                $action->($p // '{UNDEFINED}');
            }
        }
        elsif ($s eq '?') {
            my $inner = $template->[$i++];
            my $p = $fillings->{$word};
            if (ref $p eq 'CODE') {
                $p = $p->();
            }
            if ($p) {
                run_template($action, $inner, $fillings);
            }
        }
        elsif ($s eq '!') {
            my $inner = $template->[$i++];
            if (!($fillings->{$word})) {
                run_template($action, $inner, $fillings);
            }
        }
        elsif ($s eq '[') {
            my $inner = $template->[$i++];
            my $p = $fillings->{$word};
            if (ref $p eq 'CODE') {
                while (defined (my $res = $p->())) {
                    if (ref $res eq 'ARRAY') {
                        for (@$res) {
                            run_template($action, $inner, $_);
                        }
                        last;
                    }
                    else {
                        run_template($action, $inner, $res);
                    }
                }
            }
            elsif (ref $p eq 'ARRAY') {
                for (@$p) {
                    run_template($action, $inner, $_);
                }
            }
            elsif (defined $p) {
                run_template($action, $inner, $p);
            }
            else {
                $action->("{UNDEFINED}")
            }
        }
        else {
            die "Invalid template (invalid directive \"$s\")";
        }
    }
}

sub fill_template {
    my $r;
    run_template(sub { $r .= $_[0]; }, @_);
    return $r;
}
sub print_template {
    run_template(sub { print @_; }, @_);
}

1;
