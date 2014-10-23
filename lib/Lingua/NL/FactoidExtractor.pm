package Lingua::NL::FactoidExtractor;

use 5.008007;
use strict;
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(extract);
our $VERSION = '1.0';

#Declare global variables
our @factoids;

# Package variables needed for reading the xml input
my($id, $level, %rel, %word, %root, %level, %cat, %lcat, %head, %sc, %index, %begin, %wh, %ids_for_index, @ids, %clauses_done);
my $sentence_initial = 0; # boolean
my $doctitle = "";

sub extract ($$) {
  my ($inputfile,$verbose) = @_;

  print STDERR "Parsing $inputfile...\n";
    
  my @functionwords=("alle","alles","andere","anderen","beide","dat","deze","dezelfde","die","dingen","dit","een","geen","hem","hen","het","hij","ieder","iedereen","iemand","iets","ik","je","jij","meer","men","mensen","niemand","niets","ons","sommige","sommigen","u","veel","vele","velen","waaraan","waaronder","wat","we","weinig","welke","wie","wij","ze","zich","zichzelf","zij","zijn","zo","zoveel");
  my %functionwords = map { $_ => 1 } @functionwords;
  # We do not save factoids of which the subject is only a pronoun 

  open (ALP,"< $inputfile") or die "$! $inputfile\n";

  while (my $line=<ALP>) {
    if ($line =~ /<node/) {
	$level++;
    } 
    
    my $id=""; 
    if ($line =~ / id=\"([0-9]+)\" /) {
	$id=$1;
    }
    if ($line =~ / begin=\"([0-9]+)\" /) {
	my $begin = $1;
	$begin{$id} = $begin;
    }
    if ($line =~ / rel=\"([^\"]+)\"/) {
	my $rel=$1;
	$rel{$id} = $rel;
    }
    if ($line =~ / cat=\"([^\"]+)\"/) {
        my $cat=$1;
        $cat{$id} = $cat;
    }
    if ($line =~ / lcat=\"([^\"]+)\"/) {
        my $lcat=$1;
        $lcat{$id} = $lcat;
    }
    if ($line =~ / sc=\"([^\"]+)\"/) {
        my $sc=$1;
        $sc{$id} = $sc;
        # can be copula, passive, etc.
    }
    if ($line =~ / word=\"([^\"]+?)[\.\,]?\"/) {
	my $word=$1;
	$word{$id} = $word;
    }
    if ($line =~ / root=\"([^\"]+?)[\.\,]?\"/) {
	my $root=$1;
	$root{$id} = $root;
    }  
    if ($line =~ / wh=\"([^\"]+)\"/) {
        my $wh=$1;
        $wh{$id} = $wh;
    }    
    if ($line =~ / index=\"([^\"]+)\"/) {
	my $index=$1;
	$index{$id} = $index;
	push(@{$ids_for_index{$index}},$id);
    }

    $level{$id} = $level;
    if ($line =~ /<\/node>/ or $line =~ /\/>/) {
    	$level--;
    }
    
    if ($line =~ /<sentence>(.*)<\/sentence>/) {
	print "\# $1\n" if ($verbose); 
    }
  }
  close(ALP);

  @ids = sort {$a <=> $b} keys %rel;

  my $sentence_initial = 0; # boolean

  foreach my $id (sort {$a <=> $b} keys %rel) {

    if (defined $cat{$id} && $cat{$id} =~ /^(smain|ssub|sv1)$/) {
	if (not defined $clauses_done{$id}) {
	    my ($new_head_id,$subj_id,$subject,$voice) = &_generate_factoid($id,$1,"","","");
	    # return subject (and its id) of main clause because we need it in embedded clause vc
	    # (either as subject or as object in the case of a passive main clause)
	    while (defined $new_head_id) {
		if (not defined $clauses_done{$new_head_id}) {
		    $id = $new_head_id;
		    if ($voice eq "passive") {
			($new_head_id,$subj_id,$subject,$voice) = &_generate_factoid($id,"vc/body",$subj_id,"",$subject);
			# if passive, then store the subject of the main clause in the object slot of the vc
		    } else {
			($new_head_id,$subj_id,$subject,$voice) = &_generate_factoid($id,"vc/body",$subj_id,$subject,"");
		    }
		}
	    }
	}
    }
  }

  my $factoids = join("\n",@factoids);
  return $factoids;
};

sub _generate_factoid($$) {
    my ($clause_id,$clausetype,$subj_id,$subject,$object) = @_;
    
    $clauses_done{$clause_id} = 1;

    my $verb="";
    my @modifiers;
    
    my $new_head_id; 
    # if there is a vc or body in the clause then this is an embedded factoid
    # with the same subject as the main clause

    my @headed_ids = _get_headed_ids($clause_id);
    my $voice="active";
    my $verb_type="";
    my $tuple_type="factoid";
    my $obj_id;
    
    my $info = "";

    foreach my $id (@headed_ids) {
	if (defined $sc{$id} && $sc{$id} eq "passive") {
	    $voice = "passive";
	}
	my $rel = $rel{$id};
	
	if ($rel eq "hd" && $verb eq "") {
	    # if the verb slot was not yet filled with a main verb
	    #$verb = "hd:".$word{$id};
	    $verb = "hd:".$root{$id}; 
	    $verb_type = $sc{$id};
	    # use root (lemma) of verb
	} elsif ($rel eq "vc" or $rel eq "body") {
	    # get the underlying factoid recursively by returning the current id as new head id
	    $new_head_id = $id;
	} elsif ($rel eq "su" && $subject eq "") {
	    # if the subject slot was not yet filled with the subject of the main clause
	    $subject = "su:".&_get_constituent($id);
	    $subj_id = $id;
            if ($begin{$id} eq "0") {
		$sentence_initial = 1; 
            }   
	} elsif ($rel =~ /^(obj1|obj2|predc)$/) {
	    my $rel = $1;
	    if ($object =~ /su:/ && $rel eq "obj1") {
		# if the object slot already contains the subject of the main clause (in case of passive voice) don't add it again
	    } else {
		$object .= "$rel:".&_get_constituent($id);
		$obj_id = $id;
	    }
	} elsif ($rel =~ /^(mod|pc|predm|ld)$/) {
	    my $modifier = "$1:".&_get_constituent($id);
	    push (@modifiers,$modifier);
	} 
	
    }
    
    # transform passive clauses
    if ($subject eq "" && $object =~ /su:/) {
	my $m=0;
	$info .= "passive-to-active ";
	foreach my $modifier (@modifiers) {
	    if ($modifier =~ /door (.+)$/) {
		$subject = $1;
		splice(@modifiers,$m,1);
		$info .= "modifier-to-subject ";
	    } 
	    $m++;
	}
	if ($subject eq "") {
	    # if none of the modifiers starts with 'door'
	    $subject = "MEN";
	}
    }
    
    # transform double object constructions to a factoid and a definition
    if ($object =~ s/([a-z0-9]+):(.+) ([a-z0-9]+):(.+)/$1:$2|$3:$4/) {
	# double object construction, e.g. "het wordt het Silicon Valley van India genoemd"
	$info .= "double-object-to-definition ";
	$tuple_type = "definition";
	my $definition = "<$tuple_type id='$clause_id' subj='$1:$2' verb='IS' obj='$3:$4' mods='' topic='$doctitle'> # $info";
	$definition = &_clean_up($definition);
	push (@factoids,$definition);
	$tuple_type = "factoid";
    }
    
    # transform copular constructions without modifiers to definitions
    if ($verb_type eq "copula" && $subject =~ /\S/ && $object =~ /\S/){
	$verb = "IS";
	$tuple_type = "definition";
	$info .= "copula-to-definition ";
    }
 
    # resolve relative pronouns: replace die/dat/wat by the most recent NP.
    if ($subject =~ /:(die|dat|wat) *$/i) {
       my $head_id = &_get_recent_cat_id($subj_id,"np");
        $subject = "su:".&_get_constituent($head_id);
        $info .= "pron-to-np ";
    }
    if ($object =~ /:(die|dat|wat) *$/i) {
        my $head_id = &_get_recent_cat_id($obj_id,"np");
        $object = "obj:".&_get_constituent($head_id);
        $info .= "pron-to-np ";
    }    
    

    $subject = &_clean_up($subject);
    $object = &_clean_up($object);
    
    if ($object =~ s/ ([0-9]{4})$//) {
	push(@modifiers,$1);
	# if the object ends in a year then move it to the modifiers
    }
    my $modifiers = join("|",@modifiers);

    if ($sentence_initial &&  $subject =~ /^(de|het|een|die|dat|deze|dit|alle|andere|dezelfde|geen|ieder|meer|veel|vele|weinig|welke|zoveel) /i) {
        $subject = lcfirst($subject);
        # at the beginning of a sentence, lowercase determiners
    }
    my $factoid = "<$tuple_type id='$clause_id' subj='$subject' verb='$verb' obj='$object' mods='$modifiers' topic='$doctitle'> # $info";
    $factoid = &_clean_up($factoid);
    
    if ($verb eq "" or ($object eq "" && not defined ($modifiers[0]) && $verb_type =~ /(aux|passive)/)) {
	# throw away empty passives for which the sub clause has been raised, e.g. ("Dit rijk wordt")
    } else {
	push(@factoids,$factoid);
    }
    return ($new_head_id,$subj_id,"su:$subject",$voice);
}

sub _get_constituent($) {
    my ($start_id) = @_;
    my $constituent = "";
    if (not defined $cat{$start_id} && not defined $lcat{$start_id} && defined $index{$start_id}) {
	
	# find the constituent that has the same index
	if (defined $index{$start_id}) {
	  my $index = $index{$start_id};
    	  foreach my $index_id (@{$ids_for_index{$index}}) {
    	    if (defined $cat{$index_id} or defined $lcat{$index_id}) {    
		$start_id = $index_id;
		last;
	    }
	  }
	}
    }
    my $rellevel = $level{$start_id};
    $constituent .= "$word{$start_id} " if (defined $word{$start_id});
    my $id=$start_id;
    $id++;
    while ($id <= $ids[-1] && $level{$id} > $rellevel) {
	last if ($rel{$id} eq "rhd");
	$constituent .= "$word{$id} " if (defined $word{$id});	    
	$id++;
    }
    return $constituent;
}

sub _get_recent_cat_id($$) {
    my ($id,$search_cat) = @_;
    my $head_id = $id;
    while ($cat{$head_id} ne $search_cat && $head_id > 0) {
	$head_id--;
    }
    if ($head_id == 0 && $cat{$head_id} ne $search_cat){
	# if no note of type search_cat was found before then the original id is returned
	# (for example, when a sentence starts with a pronoun, there is no preceding NP)
	return $id;
    }
    return $head_id;
}

sub _get_headed_ids($) {
    my ($head_id) = @_;
    my $headlevel = $level{$head_id};
    my @headed_ids;
    my $id = $head_id;
    $id++;
    while ($id < $ids[-1] && $level{$id} > $headlevel) {
        push(@headed_ids,$id) if ($level{$id} == $headlevel+1);
        $id++;
    }
    return @headed_ids;
}

sub _clean_up($) {
    my ($string) = @_;
    $string =~ s/[a-z0-9]+: *//g;
    $string =~ s/ +/ /g;
    $string =~ s/^ //;
    $string =~ s/[,.] *$//;
    $string =~ s/=\' /=\'/g;
    $string =~ s/ \' /\' /g;
    $string =~ s/ \'>/\'>/g;
    return $string;
}


1;
__END__

=head1 NAME

Lingua::NL::FactoidExtractor - A tool for extracting factoids from Dutch texts

=head1 SYNOPSIS

use strict;
use lib "./lib";
use Lingua::NL::FactoidExtractor;

my $inputfile = "alpino.xml";
my $verbose = 1; #boolean
my $factoids = extract($inputfile,$verbose);

print $factoids;


=head1 PREREQUISITES

The Dutch Alpino-parser is a prerequisite for this module. Alpino is available under the conditions of the Gnu Lesser General Public License. See L<www.let.rug.nl/vannoord/alp/Alpino/>

=head1 DESCRIPTION

We developed a tool that extracts structured facts (I<factoids>) from running text. A factoid is a tuple of four elements: subject, verb, object and modifiers, in which the verb has been lemmatized and the object and modifier slots may be empty. As input, the factoid extractor takes text that has been syntactically parsed with the Dutch parser Alpino. 

It is straightforward to extract factoids from active main clauses that have been annotated with syntactic relations, because these relations can be directly transformed into the factoid structure, e.g.

"Rembrandt schilderde vooral veel Bijbelse taferelen"
I<Rembrandt painted mainly many Biblical scenes>
C<|Rembrandt|schilder|veel Bijbelse taferelen|vooral>

However, around 30% of the clauses in Wikipedia are passive clauses, and in many cases a person is referred to by a pronoun. We want to ensure that "A number of family members were painted by Rembrandt" gives the same factoid as "Rembrandt painted a number of family members" and that for "Rembrandt painted Biblical scenes" the same factoid is generated as for "Rembrandt, who painted Biblical scenes". For cases like these, our factoid extractor performs a number of transformations to the input clauses. We implemented the following transformations:

=item * B<Passive-to-active>: Passive clauses are transformed to active clauses, in which the subject from the passive clause takes the object position. If there is no actor in the sentence, the subject slot is filled with the empty actor 'MEN' (I<ONE>).
"De luchthaven werd op 8 juli 1964 geopend"
I<The airport was opened on July 8th, 1964>
C<MEN|open|de luchthaven|op 8 juli 1964>

=item * B<Modifier-to-subject>: If a passive clause contains a modifier starting with 'door' (\emph{by}) then this modifier is moved to the subject slot, e.g.
"De instrumenten werden opnieuw ingespeeld door de bandleden"
I<The instruments were recorded again by the band members">
C<de bandleden|speel_in|de instrumenten|opnieuw>

=item * B<Copula-to-definition>: If the verb of a clause is a copular verb (e.g. I<become>), then the object of the clause is considered to be a description of the subject. These factoids are transformed to definitions with the verb I<IS>.
"Rome werd opnieuw de hoofdstad van ItaliE<euml>
I<Rome became the capital of Italy again>
C<Rome|IS|de hoofdstad van ItaliE<euml>|opnieuw>

=item * B<Double-object-to-definition>: For clauses that have two objects, a factoid is generated that connects both objects, e.g.
"De behandeling van Crohn wordt symptomatisch genoemd"
I<The treatment of Crohn's disease is called symptomatic>
C<de behandeling van Crohn|IS|symptomatisch|>

=item * B<Pron-to-np>: If the subject or object of a clause is a relative pronoun, then we substitute it by the most recent noun phrase. This is a very local form of anaphora resolution.
"De voornaamste vertegenwoordiger was Rembrandt, die veel Bijbelse taferelen schilderde."
I<The main representative was Rembrandt, who painted many Biblical scenes.>
C<de voornaamste vertegenwoordiger|IS|Rembrandt>
C<{Rembrandt|schilder|veel Bijbelse taferelen|>

For sentences that consist of multiple clauses, multiple factoids are generated, e.g.

"Voor de onafhankelijkheid was Bangalore een belangrijke industriestad; meer recent is het een belangrijk centrum van de informatietechnologie in India geworden en wordt het wel de Silicon Valley van India genoemd."
I<Before its independence, Bangalore was an important industry town; more recently it became an important centre of information technology in India and it is called the Silicon Valley of India.>
C<Bangalore|IS|een belangrijke industriestad|Voor de onafhankelijkheid
het|IS|een belangrijk centrum van de informatietechnologie in India|meer recent
MEN|noem|het \& de Silicon Valley van India|meer recent \& wel
het|IS|de Silicon Valley van India>


=head1 KNOWN PROBLEMS

If punctuation such as a full stop or a comma is glued to a word in the Alpino output
then this punctuation also ends up in the factoids extracted from the sentence.
Work-around is to use a tokenizer that separates punctuation from words by whitespace
before parsing the sentence.


=head1 AUTHOR

Suzan Verberne, http://sverberne.ruhosting.nl

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Suzan Verberne

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.


=cut
