=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow::SLURM

=head1 DESCRIPTION

    This is the 'SLURM' implementation of an EnsEMBL eHIVE  Meadow.

=head1 Compatibility 
   

    Module version 5.3 is compatible with SLURM version 17.11.11 and eHive Meadow v5.3


=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute
    Copyright [2017] Genentech, Inc.
    Copyright [2018] Genentech, Inc.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    For this module only (SLURM.pm)
    - Jan Vogel -  you find me.  
   
 
    For other Hive questions:
    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Meadow::SLURM;

use strict;
use warnings;
use Time::Piece;
use Time::Seconds; 
use File::Temp qw(tempdir); 
use Bio::EnsEMBL::Hive::Utils ('split_for_bash','timeout');
use Time::Local ; 
use Capture::Tiny ':all';
use Scalar::Util qw(looks_like_number);
use Data::Dumper; 

use base ('Bio::EnsEMBL::Hive::Meadow');


# Module version with eHive version v80
# Module version 5.1 is compatible with Slurm 17.11.11 and eHive v94
# Module version 5.3 is compatible with Slurm 17.11.11 and eHive v94


our $VERSION = '5.3';       # Semantic version of the Meadow interface:
                            #   change the Major version whenever an incompatible change is introduced,
                            #   change the Minor version whenever the interface is extended, but compatibility is retained.




=head name

   Args:       : None
   Description : Determine the SLURM cluster_name, if an SLURM  meadow is available. 
   Exception   : Dies if command to retrieve the cluster name fails.
   Returntype  : String

=cut


sub name {  # also called to check for availability; assume Slurm is available if Slurm cluster_name can be established 
    # debugging debugging janni  
    
    #my $cmd = "sacctmgr -n -p show clusters";
    #my @lines = @{ execute_command($cmd) };
    #my @val = split /\|/, $lines[0]; 
    #my $cluster_name = $val[0]; 
    #print "Cluster name: $cluster_name\n"; 
    #return $cluster_name;  
    
    return "slurm_cluster"; 
}




=head count_pending_workers_by_rc_name 

   Args:       : None
   Description : Counts the number of pending workers of the user 
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : String

=cut 


sub count_pending_workers_by_rc_name {
    my ($self) = @_;
    
    #Needed becasue by default slurm reports all jobs
    my $username = getpwuid($<);
    
    my $jnp = $self->job_name_prefix();

    #Prefix for job is not implemented in Slurm, so need to get all
    #and parse it out
    my $cmd = "squeue --array -h -u ${username} -t PENDING -o '%j' "; 

    my $lines = execute_command($cmd); 
     
    my %pending_this_meadow_by_rc_name = ();
    my $total_pending_this_meadow = 0;

    foreach my $line (@$lines) {
        if($line=~/\b\Q$jnp\E(\S+)\-\d+(\[\d+\])?\b/)
        {
            $pending_this_meadow_by_rc_name{$1}++;
            $total_pending_this_meadow++;
        }
    }

    return (\%pending_this_meadow_by_rc_name, $total_pending_this_meadow);
}


=head count_running_workers 

   Args:       : None
   Description : Counts the number of pending workers of the user 
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : String

=cut 

sub count_running_workers {
    my $self                        = shift @_;
    my $meadow_users_of_interest    = shift @_ || [ 'all' ];

    my $jnp = $self->job_name_prefix();

    my $total_running_worker_count = 0;

    foreach my $meadow_user (@$meadow_users_of_interest)
    {
        my $cmd = "squeue --array -h -u $meadow_user -t RUNNING -o '%j' | grep ^$jnp | wc -l";
        my $lines = execute_command($cmd); 

        my $meadow_user_worker_count = $lines->[0]; 
        $meadow_user_worker_count=~s/\s+//g;       # remove both leading and trailing spaces

        $total_running_worker_count += $meadow_user_worker_count;
    }

    return $total_running_worker_count;
}


=head status_of_all_our_workers()

   Args:       : None
   Description : Counts the number of pending workers of the user 
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : Array [ worker_pid, user, status ] 

=cut 


sub status_of_all_our_workers  { 
    my $self                        = shift @_;
    my $meadow_users_of_interest    = shift @_ || [ 'all' ];

    my $jnp = $self->job_name_prefix(); # reederj_ehive_rosaprd_278-Hive-

    my @status_list = ();

    foreach my $meadow_user (@$meadow_users_of_interest)
    { 

        # PENDING, RUNNING, SUSPENDED, CANCELLED, COMPLETING, COMPLETED, CONFIGURING, FAILED, 
        # TIMEOUT, PREEMPTED, NODE_FAIL, REVOKED and SPECIAL_EXIT 
       
        # jhv : this returns the job_id. Is this job ID alwas suffixed with _1 ?  
        my $cmd = "squeue --array -h -u $meadow_user -o '%i|%T|%u' "; 

        my $lines = execute_command($cmd); 

        foreach my $line (@$lines){ 
            chomp($line); # Remove the newline from the squeue command otherwise we can't identify job correctly

            my ($worker_pid, $status, $user ) = split(/\|/, $line); 


            # TODO: not exactly sure what these are used for in the external code - 
            # this is based on the LSF status codes that were ignored
            # Do not count COMPLETED or FAILED jobs. 
            next if( ($status eq 'COMPLETED') or ($status eq 'FAILED'));

 	    push @status_list, [ $worker_pid, $user, $status ];             
        }
    }
    return \@status_list;
}


=head check_worker_is_alive_and_mine() 

   Args:       : Bio::EnsEMBL::Hive::Worker 
   Description : Checks if a worker is registered under the current logged in user. 
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : String (value of squeue command )

=cut 



sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    my $wpid = $worker->process_id();
    my $this_user = $ENV{'USER'}; 

    my $cmd = "squeue -h -u $this_user --job=$wpid 2>&1 | grep -v 'Invalid job id specified' | grep -v 'Invalid user'";
    my $lines = execute_command($cmd);  

    my $is_alive_and_mine = $lines->[0]; 
    $is_alive_and_mine =~ s/^\s+|\s+$//g;
    
    return $is_alive_and_mine;
}


=head kill_worker() 

   Args:       : None
   Description : Counts the number of pending workers of the user 
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : Array [ worker_pid, user, status ] 

=cut 

sub kill_worker {
    my ($self, $worker, $fast) = @_; 

    my $cmd = 'scancel ' . $worker->process_id();
    my $lines = execute_command($cmd); 
}




=head get_report_entries_for_process_ids() 

   Args:       : None
   Description : Gathers stats for a specific set of workers via sacct. 
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : Complex.

=cut  

sub get_report_entries_for_process_ids {
    my $self = shift @_;    # make sure we get if off the way before splicing

    my %combined_report_entries = ();

    while (my $pid_batch = join(',', map { "'$_'" } splice(@_, 0, 1))) {  # can't fit too many pids on one shell cmdline 
     #$pid_batch =~ s/\[//g;
     #$pid_batch =~ s/\]//g;

        # sacct -j 19661,19662,19663 
        #  --units=M Display values in specified unit type. [KMGTP] 
        my $cmd = "sacct -p --units=M --format JobName,JobID,ExitCode,MaxRSS,Reserved,MaxDiskRead,CPUTimeRAW,ElapsedRAW,State,DerivedExitCode,End -j $pid_batch  " ;

        warn "SLURM::get_report_entries_for_process_ids() running cmd:\n\t$cmd\n";
        my $batch_of_report_entries = $self->parse_report_source_line( $cmd );

        %combined_report_entries = (%combined_report_entries, %$batch_of_report_entries);
    }

    return \%combined_report_entries;
}



=head get_report_entries_for_process_ids() 

   Args:       : None
   Description : Gathers statistics for jobs for a time interval by running sacct.
   Exception   : Dies if command to retrieve stats fails. 
   Returntype  : Complex. 
   Caller      : Gets called from load_resource_usage.pl  

=cut  

sub get_report_entries_for_time_interval {
    my ($self, $from_time, $to_time, $username) = @_;

    my $from_timepiece = Time::Piece->strptime($from_time, '%Y-%m-%d %H:%M:%S');
    $from_time = $from_timepiece->strftime('%Y-%m-%dT%H:%M');

    my $to_timepiece = Time::Piece->strptime($to_time, '%Y-%m-%d %H:%M:%S') + 2*ONE_MINUTE;
    $to_time = $to_timepiece->strftime('%Y-%m-%dT%H:%M');

    # sacct -s CA,CD,CG,F -S 2018-02-27T16:48 -E 2018-02-27T16:50 
    # 2019-12-01 changing the sacct parameters as "CG" is not supported anymore - and the command fails fatallly 
    my $cmd = "sacct -p --units=M -s CA,CD,F,OOM  --format JobName,JobID,ExitCode,MaxRSS,Reserved,MaxDiskRead,CPUTimeRAW,ElapsedRAW,State,DerivedExitCode,End    -S $from_time -E $to_time ".($username ? "-u $username" : '') ;

    warn "SLURM::get_report_entries_for_time_interval() running cmd:\n\t$cmd\n";

    my $batch_of_report_entries = $self->parse_report_source_line( $cmd );

    return $batch_of_report_entries;
}


=head parse_report_source_line() 

   Args:       : Command ( sacct ) 
   Comment     : # Works with Slurm 17.02.9 
   Description : Parses the resource Counts the number of pending workers of the user 
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : Href 

=cut 

sub parse_report_source_line {
    my ($self, $bacct_source_line) = @_; 

    my $jnp = $self->job_name_prefix(); # reederj_ehive_rosaprd_278-Hive-

    my $lines = execute_command($bacct_source_line); 

    my %report_entry = ();

    for my $row (@$lines) { 
        chomp $row;

        # Do not parse header line. 
        if ($row =~ m/^JobName/ ){  
          next;
        }


        my @col = split(/\|/, $row);     

        my $job_name   = $col[0];   # JobName - for explanation please look at sacct command 
        my $job_id     = $col[1];   # JobID 
        my $exit_code  = $col[2];   # ExitCode 
        my $mem_used   = $col[3] || 0 ;   # MaxRSS in units=M, set in batch line  
        my $reserved_time = $col[4] || 0 ;   # Reserved / pending time ... 
        my $max_disk_read = $col[5] || 0;   # MaxDiskRead = swap in megabytes, set in batch line 
        my $total_cpu     = $col[6] || 0;   # CPUTimeRAW
        my $elapsed       = $col[7] || 0;   # ElapsedRAW 
        my $state         = $col[8] || 'UNKOWN' ;        # State : CANCELLED or CANCELLED BY 12334
        my $exception_status = $col[9];     # DerivedExitCode, not used   
        my $when_died        = $col[10] || undef; 
     
        print "DEBUG: $job_id\t$state\n";
        print "DEBUG: $row\n";


        # parse the correct state. 
        # On 2021-09-07 the state reportred in the first line was reported as 'CANCELLED by 2004512'  which rquires that we 
        # change our code to now parse the second line for the state: 
        # wuk26_ehive_quasarprd_6-Hive-100x_coverage-7655_1|10666490|0:0||00:00:00||336|12|CANCELLED by 2004512|0:0|  
        #
        if ($job_name=~ m/$jnp/) {  

         # Populate inital values. Some of these values ( exitcode, maxRss, maxDiskread, cputimeRaw and (converted) state are 
         # re-set if sacct returns a 2nd 'batch' line with more details.
          my $cause_of_death = get_cause_of_death($state); 

          $report_entry{ $job_id } = {
             # entries for 'worker' table:
                'when_died'         => $when_died, 
                'cause_of_death'    => $cause_of_death,

                 # entries for 'worker_resource_usage' table:
                 'exit_status'       => $exit_code, 
                 'exception_status'  => $cause_of_death,
                 'mem_megs'          => $mem_used,        # mem_in_units, returnd by sacct with --units=M , stored as float
                 'swap_megs'         => $max_disk_read,   # swap_in_units, stored as float
                 'pending_sec'       => convert_time_to_seconds($reserved_time),
                 'cpu_sec'           => $total_cpu ,
                 'lifespan_sec'      => $elapsed , 
            };
        } 

        #  Code below is only executed if sacct returns the additional jobid.batch line: 
	# sacct -p --units=M --format JobName,JobID,ExitCode,MaxRSS,Reserved,MaxDiskRead,CPUTimeRAW,ElapsedRAW,State,DerivedExitCode,End -j '10668505'
	# JobName|JobID|ExitCode|MaxRSS|Reserved|MaxDiskRead|CPUTimeRAW|ElapsedRaw|State|DerivedExitCode|
	# wuk26_ehive_quasarprd_6-Hive-100x_coverage-7660_1|10668505|0:0||00:00:12||336|12|CANCELLED by 2004512|0:0|
	# batch|10668505.batch|0:15|54.53M||1.94M|364|13|CANCELLED||     <------------ parse this line now !
        # extern|10668505.extern|0:0|0||0.00M|336|12|COMPLETED||

        # The 'batch' only exists if the job was in running state and contains slightly different data: 
        # - the memory used for the job ( data not reported in first line ) 
        # - the swap memory ( not reported in fist line ) 
        # - the exit status CANCELLED ( different exit status in first line : CANCELLED by 2004512)   
        # Issue: if the job times out, the correct job state is encoded in  the FIRST line: 
        # 
    # vogelj4@nl001 home/vogelj4$ sacct -p --units=M --format JobName,JobID,ExitCode,MaxRSS,Reserved,MaxDiskRead,CPUTimeRAW,ElapsedRAW,State,DerivedExitCode,End -j 12626931_5
    # JobName|JobID|ExitCode|MaxRSS|Reserved|MaxDiskRead|CPUTimeRAW|ElapsedRaw|State|DerivedExitCode|End|
    # melocars_ehive_rosaprd_1687-Hive-100x_coverage-476_1|12626931_5|0:0||00:01:26||2073816|259227|TIMEOUT|0:0|2021-09-25T13:37:10|   <-- correct state is TIMEOUT 
    # batch|12626931_5.batch|0:15|25510.32M||919.25M|2073824|259228|CANCELLED||2021-09-25T13:37:11|
    # extern|12626931_5.extern|0:0|0||0.00M|2073816|259227|COMPLETED||2021-09-25T13:37:10|

        if ( $job_name =~ m/batch/ ) { 

          $job_id =~ s/\.batch//;   

          $mem_used =~ s/M//;      # results are reported in Megabytes 422.0M and stored as float in DB
          $max_disk_read =~ s/M//; # results are reported in Megabytes 

          #my $cause_of_death = get_cause_of_death($state); 
          #print "CAuse of thead: $cause_of_death ($state)\n"; 
 
          $report_entry{ $job_id } = {
             # entries for 'worker' table:
             #   'cause_of_death'    => $cause_of_death, 

                 # entries for 'worker_resource_usage' table:
                 'exit_status'       => $exit_code, 
             #    'exception_status'  => $cause_of_death , 
                 'mem_megs'          => $mem_used,        # mem_in_units, returnd by sacct with --units=M , stored as float
                 'swap_megs'         => $max_disk_read,   # swap_in_units, stored as float
                 'cpu_sec'           => $total_cpu ,
                 'lifespan_sec'      => $elapsed , 
            };
        } 

    } 
    return \%report_entry;
}


=head submit_workers_return_meadow_pids() 

   Args:       : Command ( sacct ) 
   Comment     : # Works with Slurm 17.02.9 
   Description : Runs sbatch to submit workers to SLURM  
   Exception   : Dies if command to retrieve pending workers fails. 
   Returntype  : Href 

=cut 

sub submit_workers_return_meadow_pids {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    my $job_array_common_name               = $self->job_array_common_name($rc_name, $iteration);  
    #
    # Flag if we should submit a job array or not 
    # This is important for later in terms of what SLURM job ID we return.
    # (so the job can be reidentfied between SLURM scheduler and Database
    #
    my $array_required                      = $required_worker_count > 1; 

    my $job_array_spec                      = "1-${required_worker_count}";
    my $meadow_specific_submission_cmd_args = $self->config_get('SubmissionOptions');

    my ($submit_stdout_file, $submit_stderr_file);

    if($submit_log_subdir) {
        $submit_stdout_file = $submit_log_subdir . "/log_${rc_name}_%A_%a.out";
        $submit_stderr_file = $submit_log_subdir . "/log_${rc_name}_%A_%a.err";
    } else {
        $submit_stdout_file = '/dev/null';
        $submit_stderr_file = '/dev/null';
    }

    #No equivalent in sbatch, but can be accomplished with stdbuf -oL -eL
    #$ENV{'LSB_STDOUT_DIRECT'} = 'y';  # unbuffer the output of the bsub command
    
    #Note: job arrays share the same name in slurm and are 0-based, but this may still work  
    my @cmd;
    if ( $array_required eq "1" ) { 
      # We have to submit a job array - this will change the job ids in slurm to <job_id>_ARRAY  
      
       @cmd = ('sbatch',
                '-o', $submit_stdout_file,
                 '-e', $submit_stderr_file,
                 '-a', $job_array_spec,      # inform SLURM we submit an ARRAY 
                                             # jobs submitted with 'sbatch -a ' get different ids back when executing 
                                             # 'squeue --array -h -u <user> -o '%i|%T|%u|%A' later  
                 '-J', $job_array_common_name, 
                 split_for_bash($rc_specific_submission_cmd_args),
                 split_for_bash($meadow_specific_submission_cmd_args),
                 $worker_cmd,
	      );
    } else {  
       @cmd = ('sbatch',
                '-o', $submit_stdout_file,
                '-e', $submit_stderr_file,
                '-J', $job_array_common_name, 
                split_for_bash($rc_specific_submission_cmd_args),
                split_for_bash($meadow_specific_submission_cmd_args),
                $worker_cmd,
	      );

    }   

    print "\n\nExecuting [ ".$self->signature." ] \t\t".join(' ', @cmd)."\n\n";  

    # Hack for sbatchd 
    # Write command to file 
    my $tmp = File::Temp->new(  TEMPLATE => "slurm_job__submission.$$.XXXX", UNLINK => 1, SUFFIX => '.sh', DIR => tempdir() );
    print $tmp join(" ", @cmd); 


    # execute written file + capture STDOUT and EXIT CODE 
    my  ($stdout, $stderr, $exit) = capture {
       system ("sh $tmp") && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax  
    };

    if ( $exit ne 0 ) {  
      die("SLURM: job submission failed with exit status $exit: : $stdout $stderr"); 
    }   

    unless ( $stdout =~ m/Submitted batch job (\d+)/ ) {   
      die("ERROR: SLURM job submission returned Incorrect return value, so the SLURM JOB ID can't be parsed correctly."); 
    }  

    my @out = split /\s/,$stdout; # STDOUT is like": "Submitted batch job 2683413" 
    my $slurm_job_id = $out[-1];   

     print join(" ", @out)."\n";

    if (looks_like_number($slurm_job_id)) { 

       my $return_value;   

       # Modify the return values depending on the submission type: single job vs job array
       # as these have different indexes.  
       #
       if ( $array_required ) {   
          # We need to return all Job IDS with suffix <job>_1 <job>_2 if we submit 
          # job arrays - so they are correctly written to DB + on SLURM scheduler. 
          $return_value = [ map { $slurm_job_id.'_'.$_.'' } (1..$required_worker_count) ]; 
       }else { 

         # 
         # We submitted only a single job - so theoretically we do not have to add the <job_id>_1 suffix 
         # However - if you submit a single job to SLURM, you will still get the ID with index back later: 
         # sbatch bla.sh 
         #
         $return_value = [ $slurm_job_id ]; 
       } 
          
       print "SLURM: Submitted job ids: " . join(" ", @$return_value)."\n";  

       return $return_value; 
       #return ($array_required ? [ map { $slurm_job_id.'['.$_.']' } (1..$required_worker_count) ] : [ $slurm_job_id]); 
       #return ($array_required ? [ map { $slurm_job_id.'['.$_.']' } (1..$required_worker_count) ] : [ $slurm_job_id]); 
    } else {
       die("ERROR: SLURM Job submission failure : it looks like SURM returned a non-numerical value /job-id returned in $tmp: $stdout\n"); 
    }
    #system( @cmd ) && die "Could not submit job(s): $!, $?";  # let's abort the beekeeper and let the user check the syntax   
}



sub execute_command {
  my ($cmd) = @_;

  print "SLURM:execute_command(): Executing : $cmd\n";
  my $return_value;

  my ($stdout, $stderr, @result) = Capture::Tiny::capture (sub {
      $return_value = timeout( sub {system($cmd)}, 300 );
  });

  if ( 0 ) { 
    print "Perl DEBUGGING...\n"; 
    print "RETURN VALUE: $return_value\n"; 
    print "STDERR: $stderr\n"; 
    print "STDOUT: ".join("\n",@result)."\n"; 
    my @bla = split /\n/, $stdout;  
    print join("\n", @bla)."\n";
  }

  if ($return_value) {
     die sprintf("ERROR !!! Could not run '%s', got %s\nSTDERR %s\n", $cmd, $return_value, $stderr) ;
  }  
  my @lines = split /\n/, $stdout; 
  return \@lines;
}



sub get_current_worker_process_id {
    my ($self) = @_;

    my $slurm_jobid           = $ENV{'SLURM_JOBID'};
    my $slurm_array_job_id    = $ENV{'SLURM_ARRAY_JOB_ID'};
    my $slurm_array_task_id   = $ENV{'SLURM_ARRAY_TASK_ID'};

    #We have a slurm job
    if(defined($slurm_jobid))
    {
        #We have an array job
        if(defined($slurm_array_job_id) and defined($slurm_array_task_id))
        {
            return "$slurm_array_job_id\_$slurm_array_task_id";
        }
        else
        {
            return $slurm_jobid;
        }
    }
    else
    {
        die "Could not establish the process_id";
    }
} 


=head get_cause_of_death() 

   Args:       : Slurm job state 
   Description : Translates a SLURM job state into an eHive cause-of-death 
   Exception   : None 
   Returntype  : String

=cut 



sub get_cause_of_death { 
   my ($state) = @_;   

    my %slurm_status_2_cod = (
       'TIMEOUT'           => 'RUNLIMIT',
       'FAILED'            => 'CONTAMINATED',
       'OUT_OF_MEMORY'     => 'MEMLIMIT', 
       'CANCELLED'         => 'KILLED_BY_USER',  
    );


    my $cod = $slurm_status_2_cod{$state} ;  
    #unless ( $cod ) { 
    #   print "DEBUG: Weird job state: $state - setting status to UNKNOWN\n";
    #   $cod = "UNKNOWN" ; 
    #}  

    print "get_cause_of_death(): Translating state from --$state-- ==> --$cod--\n";
    return $cod; 
}


=head convert_to_seconds(dd-hh:mm:sec); 

   Args:       : String describing time in sacct format 
   Description : Translates slurm time string into raw seconds for elapsed time 
   Exception   : None 
   Returntype  : String
   Example     :  
                 - convert_to_seconds(5-01:59:33); 
                 - convert_to_seconds(01:59:33); 
=cut 


sub convert_time_to_seconds {
 my ($string) = @_;
 my $days = 0;
 my $hr_min_sec = $string; ;

  if ( $string =~ m/-/ ) {
     ($days, $hr_min_sec) = split /\-/,$string;
  }

   my ($hr,$min,$sec) = split /:/,$hr_min_sec;
   return  $days * 24 * 60 * 60 +   $hr*60*60 + $min*60 + $sec ;
}



1;
