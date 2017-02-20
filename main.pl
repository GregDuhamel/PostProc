#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use FileHandle;
use Text::ParseWords;
use File::Copy;
use File::Spec::Win32;
use English qw(-no_match_vars);

BEGIN {
	use constant TRUE  => 42;
	use constant FALSE => 0;
	our $VERSION = 1.08;

	# No Buffering on perl I/O to STDOUT and STDERR:
	FileHandle::autoflush STDERR 1;
	FileHandle::autoflush STDOUT 1;
}

sub parseOptions {
	our %Options;
	Getopt::Long::GetOptions(
		'h|help'    => \$Options{'help'},
		'm|man'     => \$Options{'man'},
		'f|file=s'  => \$Options{'file'},
		'PART=s'    => \$Options{'part'},
		'IDF=s'     => \$Options{'idf'},
		'IDT=s'     => \$Options{'idt'},
		'IDTU=s'    => \$Options{'idtu'},
		'FNAME=s'   => \$Options{'fname'},
		'FDATE=i'   => \$Options{'fdate'},
		'FDATE6:i'  => \$Options{'fdate6'},
		'FDATE36:s' => \$Options{'fdate36'},
		'FTIME=i'   => \$Options{'ftime'},
		'FTIME6:i'  => \$Options{'ftime6'},
		'PARM=s'    => \$Options{'parm'},
		'PARM14:s'  => \$Options{'parm14'},
		'PARM16:s'  => \$Options{'parm16'},
		'PARM16F:s' => \$Options{'parm16f'},
		'PARM17:s'  => \$Options{'parm17'},
		'PARM26:s'  => \$Options{'parm26'},
		'PARM32:s'  => \$Options{'parm32'},
		'PARM103:s' => \$Options{'parm103'},
		'PARM124:s' => \$Options{'parm124'},
		'SAPPL:s'   => \$Options{'sappl'}
	) or Pod::Usage::pod2usage( -exitval => 1, -verbose => 1 );

	if ( defined $Options{'help'} ) {
		Pod::Usage::pod2usage( -exitval => 0, -verbose => 1 );
	}
	if ( defined $Options{'man'} ) {
		Pod::Usage::pod2usage( -exitval => 0, -verbose => 2 );
	}

	unless ( defined $Options{'part'}
		&& defined $Options{'idf'}
		&& defined $Options{'idt'}
		&& defined $Options{'idtu'}
		&& defined $Options{'fname'}
		&& defined $Options{'fdate'}
		&& defined $Options{'ftime'} )
	{
		print STDERR "[ERROR]["
		  . localtime()
		  . "] Some mandatory command line option(s) is/are missing (PART, IDF, IDT, IDTU, FNAME, FDATE, FTIME)\n";
		Pod::Usage::pod2usage( -exitval => 1, -verbose => 1 );
	}

	unless ( defined $Options{'file'} && -f $Options{'file'} ) {
		print STDERR "[ERROR]["
		  . localtime()
		  . "] Mandatory option -f / --file not provided or value provided is not a valid file.\n";
		Pod::Usage::pod2usage( -exitval => 1, -verbose => 1 );
	}
	return (TRUE);
}

sub replaceVarsByOptionsValues {
	my $string = shift;
	our %Options;

	print STDOUT "[DEBUG]["
	  . localtime()
	  . "] String replacement start on string : $string \n";

	my @keys = keys(%Options);
	foreach my $key (@keys) {
		if ( exists $Options{$key} ) {
			$string =~ s/&$key/$Options{$key}/gixms;
		}
	}

	print STDOUT "[DEBUG]["
	  . localtime()
	  . "] String replacement done, final string is : $string \n";

	return ($string);
}

sub readPostProcFile {
	our %Options;

	print STDOUT "[INFO]["
	  . localtime()
	  . "] Will attempt to open file : $Options{'file'} \n";
	open( my $fh, '<:encoding(UTF-8)', $Options{'file'} )
	  or die "[ERROR]["
	  . localtime()
	  . "] Can't open file $Options{'file'} Reason : $OS_ERROR\n";
	print STDOUT "[INFO][" . localtime() . "] File successfully opened.\n";

	my $line_count = 0;
	our %LinesToExecute;

	while ( my $line = <$fh> ) {
		chomp $line;
		$line_count++;
		my $firschar = substr( ($line), 0, 1 );
		next if $firschar eq q{#};
		my @CSVLine = Text::ParseWords::parse_line( q{;}, 1, $line );
		if ( $CSVLine[0] && $CSVLine[0] =~ $Options{'idf'} ) {
			$LinesToExecute{$line_count} = \@CSVLine;
			print STDOUT "[INFO]["
			  . localtime()
			  . "] Line $line_count successfully parsed.\n";
		}
	}
	print STDOUT "[INFO][" . localtime() . "] Close file $Options{'file'}\n";
	close($fh) or die "[ERROR][" . localtime() . "] : $OS_ERROR";
	print STDOUT "[INFO][" . localtime() . "] File successfully closed.\n";
	return (TRUE);
}

sub execSystemCommand {
	our @CurrentLine;

	my $command = $CurrentLine[2];

	$command = replaceVarsByOptionsValues($command);

	print STDOUT "[INFO]["
	  . localtime()
	  . "] Will attempt to execute command : $command\n";

	system($command);

	if ( $CHILD_ERROR == -1 ) {
		print STDERR "[ERROR]["
		  . localtime()
		  . "] Failed to execute: $OS_ERROR\n";
		return (FALSE);
	}
	elsif ( $CHILD_ERROR & 127 ) {
		printf STDERR "[ERROR]["
		  . localtime()
		  . "] Command died with signal %d, %s coredump\n",
		  ( $CHILD_ERROR & 127 ), ( $CHILD_ERROR & 128 ) ? 'with' : 'without';
		return (FALSE);
	}
	else {
		printf STDOUT "[INFO]["
		  . localtime()
		  . "] Command exited with value %d\n", $CHILD_ERROR >> 8;
		return (TRUE);
	}
}

sub execPostProc {
	our @CurrentLine;

	unless ( $CurrentLine[4] && $CurrentLine[5] && $CurrentLine[6] ) {
		print STDERR "[ERROR]["
		  . localtime()
		  . "] Insufficient DollarU arguments, you miss one of those : DollarU Session, Uproc or AG.\n";
		return (FALSE);
	}

	print STDOUT "[INFO]["
	  . localtime()
	  . "] Will now attempt to execute uXorder to $CurrentLine[3], Session: $CurrentLine[4], Uproc: $CurrentLine[5], MU: $CurrentLine[6] \n";

	  
	 my $tmp = $CurrentLine[2]; 
	 $CurrentLine[2] = "e:\\win32app\\dollarU\\BNPPAR\\exec\\uxordre.exe SOC=BNPPAR NODE=$CurrentLine[3] ESP=X SES=$CurrentLine[4] VSES=000 UPR=$CurrentLine[5] VUPR=000 MU=$CurrentLine[6] $CurrentLine[7])";
	  
	unless ( execSystemCommand() ) {
		$CurrentLine[2] = $tmp;
		print STDERR "[ERROR]["
		  . localtime()
		  . "] Exec for current line failed.\n";
		  return(FALSE);
	}
	$CurrentLine[2] = $tmp;
	return (TRUE);
}

sub copyFile {
	our @CurrentLine;
	our %Options;

	my $dest = $CurrentLine[1];

	$dest = replaceVarsByOptionsValues($dest);

	unless ( -f $Options{'fname'} ) {
		print STDERR "[ERROR]["
		  . localtime()
		  . "] File $Options{'fname'} is not valid or does not exist.\n";
		return (FALSE);
	}

	my ( $vol, $dir, $file ) = File::Spec::Win32->splitpath($dest);

	my $directory = "$vol$dir";

	unless ( -d $directory ) {
		print STDERR "[ERROR]["
		  . localtime()
		  . "] Folder $directory is not valid or does not exist.\n";
		return (FALSE);
	}

	print STDOUT "[INFO]["
	  . localtime()
	  . "] Will attempt to copy file $Options{'fname'} in $dest \n";

	unless ( File::Copy::copy( $Options{'fname'}, $dest ) ) {
		print STDERR "[ERROR]["
		  . localtime()
		  . "] Can't copy file : $OS_ERROR \n";
		exit(1);
	}
	print STDOUT "[INFO][" . localtime() . "] File successfully copied.\n";
	return (TRUE);
}

sub processLine {
	our @CurrentLine;

	if ( $CurrentLine[1] && $CurrentLine[1] =~ /NoCopy/gi ) {
		print STDOUT "[INFO]["
		  . localtime()
		  . "] Found NoCopy for current line or line empty. Nothing to do.\n";
	}
	elsif ( $CurrentLine[1] ) {
		print STDOUT "[INFO]["
		  . localtime()
		  . "] Will now try to copy file for current line.\n";
		unless ( copyFile() ) {
			print STDERR "[ERROR]["
			  . localtime()
			  . "] Copy for current line failed.\n";
			return (FALSE);
		}
		print STDOUT "[INFO]["
		  . localtime()
		  . "] File copied successfully for current line.\n";
	}
	else {
		print STDOUT "[WARN]["
		  . localtime()
		  . "] Line empty on copy for current line.\n";
	}

	if ( $CurrentLine[2] && $CurrentLine[2] =~ /NoSystem/gi ) {
		print STDOUT "[INFO]["
		  . localtime()
		  . "] Found NoSystem for current line or line empty. Nothing to do.\n";
	}
	elsif ( $CurrentLine[2] ) {
		print STDOUT "[INFO]["
		  . localtime()
		  . "] Will now try to exec system command for current line.\n";
		unless ( execSystemCommand() ) {
			print STDERR "[ERROR]["
			  . localtime()
			  . "] Exec for current line failed.\n";
		}
		print STDOUT "[INFO]["
		  . localtime()
		  . "] System command executed for current line.\n";
	}
	else {
		print STDOUT "[WARN]["
		  . localtime()
		  . "] Line empty on system exec for current line.\n";
	}

	if ( $CurrentLine[3] && $CurrentLine[3] =~ /NoProc/gi ) {
		print STDOUT "[INFO]["
		  . localtime()
		  . "] Found NoProc for current line or line empty. Nothing to do.\n";
	}
	elsif ( $CurrentLine[3] ) {
		print STDOUT "[INFO]["
		  . localtime()
		  . "] Will now try to exec PostProc for current line.\n";
		unless ( execPostProc() ) {
			print STDERR "[ERROR]["
			  . localtime()
			  . "] PostProc for current line failed.\n";
		}
		print STDOUT "[INFO]["
		  . localtime()
		  . "] PostProc executed successfully for current line.\n";
	}
	else {
		print STDOUT "[WARN]["
		  . localtime()
		  . "] Line empty on PostProc for current line.\n";
	}
	return (TRUE);
}

sub Main {
	our %Options;
	our %LinesToExecute;

	parseOptions();

	readPostProcFile();

	my @keys = keys(%LinesToExecute);
	my $size = @keys;
	if ( $size > 0 ) {
		print STDOUT "[INFO]["
		  . localtime()
		  . "] Found $size line(s) in file $Options{'file'} with IDF=$Options{'idf'} \n";
		foreach my $key (@keys) {
			our @CurrentLine = @{ $LinesToExecute{$key} };
			print STDOUT "[DEBUG]["
			  . localtime()
			  . "] Ligne ."
			  . Data::Dumper::Dumper(@CurrentLine) . "\n";
			processLine();
		}
	}
	else {
		print STDOUT "[WARN]["
		  . localtime()
		  . "] No line found in file $Options{'file'} with IDF=$Options{'idf'} \n";
	}
	exit(0);
}
Main();

__END__

=head1 NAME

	PostExec - CFT post execution action as described in fichier_final.csv

=head1 VERSION

	This documentation refers to yourprog version 1.08.
	
=head1 USAGE

	PostExec -f fichier_final.csv --PART=BOUCLE --IDF=TESTGREG --IDT=B1619553 --IDTU=A00067JV --FNAME="H:\recept\rcv\test\TESTGREG\cra.txt --FDATE=20170216 --FTIME=19553100 --PARM="cra.txt"
	
=head1 REQUIRED ARGUMENTS

	

=head1 OPTIONS

=over 4

=item B<-help>

	Print a brief help message and exits.
	
=item B<-man>

	Prints the manual page and exits

=item B<-file>
	
	Absolute path to PostExec file (fichier_final.csv). Mandatory.

=item B<-PART>

	The id of the partner responsible for the transfer. Mandatory.

=item B<-IDF>

	File identifier. Mandatory.

=item B<-IDT>

	string8 - Transfer identifier. Identifies a transfer for a given partner and transfer direction. Mandatory.
	
=item B<-IDTU>

	string8 - Catalog identifier. It is a unique, local reference to a transfer. Mandatory.
	
=item B<-FNAME>

	string512 - Name of the physical receiver file, filename or complete path name, of the directory. Mandatory.

=item B<-FTIME>

	int8 - File creation time (HHMMSSCC).

=item B<-FDATE>

	File creation date.
	
=item B<-FPARM>

	string512 - User message sent to the partner with the file transfer.

=item B<-SAPPL>

	The identifier of the file sender application. Depending on the protocol profile, it is:
		- string8  for PeSIT D CFT, PeSIT E, PeSIT SIT
		- string48 for PeSIT E CFT/CFT

=back

=head1 DESCRIPTION
	
	PostExec script will execute post file receive action as described in file "fichier_final.csv".
	
=head1 DIAGNOSTICS

=head1 EXIT STATUS

=head1 CONFIGURATION

=head1 DEPENDENCIES

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 LICENSE AND COPYRIGHT

=cut
