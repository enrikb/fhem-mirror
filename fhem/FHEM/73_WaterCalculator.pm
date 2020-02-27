# $Id$
########################################################################################################################
#
#     73_WaterCalculator.pm
#     Observes a reading of a device which represents the actual counter (e.g. OW_devive) 
#     acting as Water counter, calculates the corresponding values and writes them back to 
#     the counter device.
#     Written and best viewed with Notepad++ v.6.8.6; Language Markup: Perl
#	  This is based on "ElectricityCalulator" from Matthias Deeke. All rights to him.
#
#     Author                     : Matthias Deeke; J�rgen Brugger 
#     e-mail                     : matthias.deeke(AT)deeke(DOT)eu; juergen.brugger(AT)gmail(DOT)com
#     Fhem Forum                 : https://forum.fhem.de/index.php?topic=58579.0;topicseen
#     Fhem Wiki                  : Not yet implemented
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#     fhem.cfg: define <devicename> WaterCalculator <regexp>
#
#     Example 1:
#     define myWaterCalculator WaterCalculator myWaterCounter:CounterA.*
#
########################################################################################################################

########################################################################################################################
# List of open Problems / Issues:
#
#   - EXPERIMENTAL VERSION ONLY!
#
########################################################################################################################

package main;
use strict;
use warnings;

###START###### Initialize module ##############################################################################START####
sub WaterCalculator_Initialize($)
{
    my ($hash)  = @_;
	
    $hash->{STATE}				= "Init";
    $hash->{DefFn}				= "WaterCalculator_Define";
    $hash->{UndefFn}			= "WaterCalculator_Undefine";
    $hash->{GetFn}           	= "WaterCalculator_Get";
	$hash->{SetFn}           	= "WaterCalculator_Set";
    $hash->{AttrFn}				= "WaterCalculator_Attr";
	$hash->{NotifyFn}			= "WaterCalculator_Notify";
	$hash->{DbLog_splitFn}   	= "WaterCalculator_DbLog_splitFn";
	$hash->{NotifyOrderPrefix}	= "10-";   							# Want to be called before the rest

	$hash->{AttrList}       	= "disable:0,1 " .
								  "header " .
								  "WaterCounterOffset " .
								  "WaterCubicPerCounts " .
								  "BasicPricePerAnnum " .
								  "WaterPricePerCubic " .
								  "MonthlyPayment " .
								  "MonthOfAnnualReading " .
								  "ReadingDestination:CalculatorDevice,CounterDevice " .
								  "WFRUnit:l/min,m&sup3;/min,m&sup3;/h " .
								  "Currency:&#8364;,&#163;,&#36; " .
								  "DecimalPlace:3,4,5,6,7 " .
								  $readingFnAttributes;
}
####END####### Initialize module ###############################################################################END#####

###START###### Activate module after module has been used via fhem command "define" ##########################START####
sub WaterCalculator_Define($$$)
{
	my ($hash, $def)              = @_;
	my ($name, $type, $RegEx, $RegExst) = split("[ \t]+", $def, 4);

	### Check whether regular expression has correct syntax
	if(!$RegEx || $RegExst) 
	{
		my $msg = "Wrong syntax: define <name> WaterCalculator device[:event]";
		return $msg;
	}

	### Check whether regular expression is misleading
	eval { "Hallo" =~ m/^$RegEx$/ };
	return "Bad regexp: $@" if($@);
	$hash->{REGEXP} = $RegEx;	

	### Writing values to global hash
	notifyRegexpChanged($hash, $RegEx);
	$hash->{NAME}							= $name;
	$hash->{STATE}              			= "active";
	$hash->{REGEXP}             			= $RegEx;
    
	if(defined($attr{$hash}{WFRUnit}))
	{
		if    ($attr{$hash}{WFRUnit} eq "l/min" )      {$hash->{system}{WFRUnitFactor} = 1         ;}
		elsif ($attr{$hash}{WFRUnit} eq "m&sup3;/min") {$hash->{system}{WFRUnitFactor} = 0.001     ;}
		elsif ($attr{$hash}{WFRUnit} eq "m&sup3;/h")   {$hash->{system}{WFRUnitFactor} = 0.06      ;}
		else                                           {$hash->{system}{WFRUnitFactor} = 1         ;}
	}
	else
	{
                                                   $hash->{system}{WFRUnitFactor} = 1;
	}

	### Convert Decimal Places 
	if(defined($attr{$hash}{DecimalPlace})) {
		$hash->{system}{DecimalPlace} = "%." . $attr{$hash}{DecimalPlace} . "f";
	
	}
	else {
		$hash->{system}{DecimalPlace} = "%.3f";
	}
	
	### Defining notify trigger
	$hash->{NOTIFYDEV} = $RegEx;
		
	### Writing log entry
	Log3 $name, 5, $name. " : WaterCalculator - Starting to define module";

	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub WaterCalculator_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	

	Log3 $name, 3, $name. " WaterCalculator- The Water calculator has been undefined. Values corresponding to water meter will no longer calculated";
	
	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub WaterCalculator_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
	
	### Check whether "disable" attribute has been provided
	if ($a[2] eq "disable")
	{
		if    ($a[3] eq 0)
		{	
			$hash->{STATE} = "active";
		}
		elsif ($a[3] eq 1)		
		{	
			$hash->{STATE} = "disabled";
		}
	}
	
	### Check whether "WFRUnit" attribute has been provided
	if ($a[2] eq "WFRUnit")
	{
		if    ($a[3] eq "l/min" )      {$hash->{system}{WFRUnitFactor} = 1          ;}
		elsif ($a[3] eq "m&sup3;/min") {$hash->{system}{WFRUnitFactor} = 0.001      ;}
		elsif ($a[3] eq "m&sup3;/h")   {$hash->{system}{WFRUnitFactor} = 0.06       ;}
		else                           {$hash->{system}{WFRUnitFactor} = 1          ;}
	}

	### Convert Decimal Places 
	elsif ($a[2] eq "DecimalPlace") {
		if (($a[3] >= 3) && ($a[3] <= 8)) {
			$hash->{system}{DecimalPlace} = "%." . $a[3] . "f";
		}
		else {
			$hash->{system}{DecimalPlace} = "%.3f";
		}
	}
	
	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####


###START###### Provide units for DbLog database via DbLog_splitFn #############################################START####
sub WaterCalculator_DbLog_splitFn($$)
{
	my ($event, $name)	= @_;
	my ($reading, $value, $unit);
    my $hash 			= $defs{$name};
	my @argument		= split("[ \t][ \t]*", $event);
	
	### Delete ":" and everything behind in readings name
	$argument[0] =~ s/:.*//;
 
	### Log entries for debugging
	Log3 $name, 5, $name. " : WaterCalculator_DbLog_splitFn - Content of event                   : " . $event;
	Log3 $name, 5, $name. " : WaterCalculator_splitFn - Content of argument[0]                   : " . $argument[0];
	Log3 $name, 5, $name. " : WaterCalculator_splitFn - Content of argument[1]                   : " . $argument[1];


	### If the reading contains "_ConsumptionCost" or "_FinanceReserve"
	if (($argument[0] =~ /_ConsumptionCost/) || ($argument[0] =~ /_FinanceReserve/))
	{
		### Log entries for debugging
		Log3 $name, 5, $name. " : WaterCalculator_DbLog_splitFn - ConsumptionCost-Reading detected    : " . $argument[0];
		
		### Get values being changed from hash
		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = $attr{$hash}{Currency};
	}
	### If the reading contains "_Flow"
	elsif ($argument[0] =~ /_Flow/)
	{
		### Log entries for debugging
		Log3 $name, 5, $name. " : WaterCalculator_DbLog_splitFn - Flow-Reading detected         : " . $argument[0];
		
		### Get values being changed from hash
 		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = $attr{$hash}{WFRUnit};
	}
	### If the reading contains "_Counter" or "_Last" or ("_Consumption" but not "_ConsumptionCost") or "_PrevRead"
	elsif (($argument[0] =~ /_Counter/) || ($argument[0] =~ /_Last/) || (($argument[0] =~ /_Consumption/) && ($argument[0] !~ /_ConsumptionCost/)) || ($argument[0] =~ /_PrevRead/))
	{
		### Log entries for debugging
		Log3 $name, 5, $name. " : WaterCalculator_DbLog_splitFn - Counter/Consumption-Reading detected: " . $argument[0];
		
		### Get values being changed from hash
		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = "m&sup3;";
	}
	### If the reading is unknown
	else
	{
		### Log entries for debugging
		Log3 $name, 5, $name. " : WaterCalculator_DbLog_splitFn - unspecified-Reading detected   : " . $argument[0];
		
		### Get values being changed from hash
		$reading = $argument[0];
		$value   = $argument[1];
		$unit    = "";
	}
	return ($reading, $value, $unit);
}
####END####### Provide units for DbLog database via DbLog_splitFn ##############################################END#####


###START###### Manipulate reading after "get" command by fhem #################################################START####
sub WaterCalculator_Get($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get WaterCalculator\" needs at least one argument";
	}
		
	my $WaterCalcName = shift @a;
	my $reading  = shift @a;
	my $value; 
	my $ReturnMessage;

	if(!defined($hash->{helper}{gets}{$reading}))
	{
		my @cList = keys %{$hash->{helper}{gets}};
		return "Unknown argument $reading, choose one of " . join(" ", @cList);

		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - get list: " . join(" ", @cList);
	}
	
	if ( $reading ne "?")
	{
		### Write current value
		$value = ReadingsVal($WaterCalcName,  $reading, undef);
		
		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - get " . $reading . " with value: " . $value;

		### Create ReturnMessage
		$ReturnMessage = $value;
	}
	
	return($ReturnMessage);
}
####END####### Manipulate reading after "get" command by fhem ##################################################END#####

###START###### Manipulate reading after "set" command by fhem #################################################START####
sub WaterCalculator_Set($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"set WaterCalculator\" needs at least one argument";
	}
		
	my $WaterCalcName = shift @a;
	my $reading  = shift @a;
	my $value = join(" ", @a);
	my $ReturnMessage;

	if(!defined($hash->{helper}{gets}{$reading})) 
	{
		my @cList = keys %{$hash->{helper}{sets}};
		return "Unknown argument $reading, choose one of " . join(" ", @cList);

		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - set list: " . join(" ", @cList);
	}
	
	if ( $reading ne "?")
	{
		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - set " . $reading . " with value: " . $value;
		
		### Write current value
		readingsSingleUpdate($hash, $reading, $value, 1);
		
		### Create ReturnMessage
		$ReturnMessage = $WaterCalcName . " - Successfully set " . $reading . " with value: " . $value;
	}
	
	return($ReturnMessage);
}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

###START###### Calculate water meter values on changed events ###################################################START####
sub WaterCalculator_Notify($$)
{
	### Define variables
	my ($WaterCalcDev, $WaterCountDev)	= @_;
	my $WaterCalcName 					= $WaterCalcDev->{NAME};
	my $WaterCountName					= $WaterCountDev->{NAME};
	my $WaterCountNameEvents			= deviceEvents($WaterCountDev, 1);
	my $NumberOfChangedEvents			= int(@{$WaterCountNameEvents});
 	my $RegEx							= $WaterCalcDev->{REGEXP};

	### Check whether the Water calculator has been disabled
	if(IsDisabled($WaterCalcName))
	{
		return "";
	}
	
	### Check whether all required attributes has been provided and if not, create them with standard values
	if(!defined($attr{$WaterCalcName}{BasicPricePerAnnum}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{BasicPricePerAnnum} 	= 0;

		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute BasicPricePerAnnum was missing and has been set to 0";
	}
	if(!defined($attr{$WaterCalcName}{WaterCounterOffset}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{WaterCounterOffset} 		= 0;

		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute WaterCounterOffset was missing and has been set to 0";
	}
	if(!defined($attr{$WaterCalcName}{WaterCubicPerCounts}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{WaterCubicPerCounts} 		= 1;

		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute WaterCubicPerCounts was missing and has been set to 1 counts/qm";

	}
	if(!defined($attr{$WaterCalcName}{WaterPricePerCubic}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{WaterPricePerCubic} 		= 2.00;

		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute WaterPricePerCubic was missing and has been set to 2.00 currency-unit/water Consumption-unit";
	}
	if(!defined($attr{$WaterCalcName}{MonthlyPayment}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{MonthlyPayment} 		= 0;

		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute MonthlyPayment was missing and has been set to 0 currency-units";
	}
	if(!defined($attr{$WaterCalcName}{MonthOfAnnualReading}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{MonthOfAnnualReading} 	= 5;

		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute MonthOfAnnualReading was missing and has been set to 5 which is the month May";
	}
	if(!defined($attr{$WaterCalcName}{Currency}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{Currency} 	            = "&#8364;";

		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute Currency was missing and has been set to &#8364;";
	}
	if(!defined($attr{$WaterCalcName}{WFRUnit}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{WFRUnit}         = "l/min";
		$WaterCalcDev->{system}{WFRUnitFactor} = 1;
		
		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute WFRUnit was missing and has been set to l_min";
	}
	if(!defined($attr{$WaterCalcName}{ReadingDestination}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{ReadingDestination}     = "CalculatorDevice";
		
		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute ReadingDestination was missing and has been set to CalculatorDevice";
	}
	if(!defined($attr{$WaterCalcName}{room}))
	{
		if(defined($attr{$WaterCountName}{room}))
		{
			### Set attribute with standard value since it is not available
			$attr{$WaterCalcName}{room} 				= $attr{$WaterCountName}{room};

			### Writing log entry
			Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute room was missing and has been set to the same room of the water meter: " . $attr{$WaterCountName}{room};
		}
		else
		{
			### Set attribute with standard value since it is not available
			$attr{$WaterCalcName}{room} 				= "Water Consumption Counter";

			### Writing log entry
			Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute room was missing and has been set to Water Consumption Counter";
		}
	}
	if(!defined($attr{$WaterCalcName}{DecimalPlace}))
	{
		### Set attribute with standard value since it is not available
		$attr{$WaterCalcName}{DecimalPlace}         = 3;
		$WaterCalcDev->{system}{DecimalPlace} = "%.3f";
		
		### Writing log entry
		Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - The attribute DecimalPlace was missing and has been set to 3";
	}

	### For each feedback on in the array of defined regexpression which has been changed
	for (my $i = 0; $i < $NumberOfChangedEvents; $i++) 
	{
		### Extract event
		my $s = $WaterCountNameEvents->[$i];

		### Filtering all events which do not match the defined regex
		if(!defined($s))
		{
			next;
		}
		my ($WaterCountReadingName, $WaterCountReadingValueCurrent) = split(": ", $s, 2); # resets $1
		if("$WaterCountName:$s" !~ m/^$RegEx$/)
		{
			next;
		}
		
		### Extracting value
		if(defined($1)) 
		{
			my $RegExArg = $1;

			if(defined($2)) 
			{
				$WaterCountReadingName = $1;
				$RegExArg = $2;
			}

			$WaterCountReadingValueCurrent = $RegExArg if(defined($RegExArg) && $RegExArg =~ m/^(-?\d+\.?\d*)/);
		}
		if(!defined($WaterCountReadingValueCurrent) || $WaterCountReadingValueCurrent !~ m/^(-?\d+\.?\d*)/)
		{
			next;
		}
		
		###Get current Counter and transform in water consumption (qm) as read on mechanic water meter
		   $WaterCountReadingValueCurrent      = $1 * $attr{$WaterCalcName}{WaterCubicPerCounts} + $attr{$WaterCalcName}{WaterCounterOffset};
		my $WaterCountReadingTimestampCurrent  = ReadingsTimestamp($WaterCountName,$WaterCountReadingName,0);		

		
		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator Begin_______________________________________________________________________________________________________________________________";
		
		### Create name and destination device for general reading prefix
		my $WaterCalcReadingPrefix;
		my $WaterCalcReadingDestinationDevice;
		my $WaterCalcReadingDestinationDeviceName;
		if ($attr{$WaterCalcName}{ReadingDestination} eq "CalculatorDevice")
		{
			$WaterCalcReadingPrefix					= ($WaterCountName . "_" . $WaterCountReadingName);
			$WaterCalcReadingDestinationDevice		=  $WaterCalcDev;
			$WaterCalcReadingDestinationDeviceName	=  $WaterCalcName;

			### Create Log entries for debugging
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Attribut ReadingDestination has been set to CalculatorDevice";			
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReadingPrefix                     : " . $WaterCalcReadingPrefix;
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReadingDestinationDevice          : " . $WaterCalcReadingDestinationDevice;
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReadingDestinationDeviceName      : " . $WaterCalcReadingDestinationDeviceName;

		}
		elsif ($attr{$WaterCalcName}{ReadingDestination} eq "CounterDevice")
		{
			$WaterCalcReadingPrefix 				=  $WaterCountReadingName;
			$WaterCalcReadingDestinationDevice		=  $WaterCountDev;
			$WaterCalcReadingDestinationDeviceName	=  $WaterCountName;

			### Create Log entries for debugging
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Attribut ReadingDestination has been set to CounterDevice";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReadingPrefix                     : " . $WaterCalcReadingPrefix;
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReadingDestinationDevice          : " . $WaterCalcReadingDestinationDevice;
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReadingDestinationDeviceName      : " . $WaterCalcReadingDestinationDeviceName;
		}
		else
		{
			### Create Log entries for debugging
			Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - Attribut ReadingDestination has not been set up correctly. Skipping event.";
			
			### Skipping event
			next;
		}
		
		### Restore previous Counter and if not available define it with "undef"
		my $WaterCountReadingTimestampPrevious = ReadingsTimestamp($WaterCalcReadingDestinationDeviceName,  "." . $WaterCalcReadingPrefix . "_PrevRead", undef);
		my $WaterCountReadingValuePrevious     =       ReadingsVal($WaterCalcReadingDestinationDeviceName,  "." . $WaterCalcReadingPrefix . "_PrevRead", undef);

		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCountReadingValuePrevious             : " . $WaterCountReadingValuePrevious;
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReadingPrefix_PrevRead            : " . $WaterCalcReadingPrefix . "_PrevRead";

		### Find out whether there has been a previous value being stored
		if(defined($WaterCountReadingValuePrevious))
		{
			### Write current water Consumption as previous water Consumption for future use in the WaterCalc-Device
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix. "_PrevRead", sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent)),1);

			### Create Log entries for debugging
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Previous value found. Continuing with calculations";
		}
		### If not: save value and quit loop
		else
		{
			### Write current water Consumption as previous Value for future use in the WaterCalc-Device
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix. "_PrevRead", sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent)),1);

			### Create Log entries for debugging
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Previous value NOT found. Skipping Loop";
			
			### Jump out of loop since there is nothing to do anymore than to wait for the next value
			next;
		}

		###### Find out whether the device has been freshly defined and certain readings have never been set up yet or certain readings have been deleted
		### Find out whether the reading for the daily start value has not been written yet 
		if(!defined(ReadingsVal($WaterCalcReadingDestinationDeviceName,  $WaterCalcReadingPrefix . "_CounterDay1st", undef)))
		{
			### Save current water Consumption as first reading of day = first after midnight and reset min, max value, value counter and value sum
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,       $WaterCalcReadingPrefix . "_CounterDay1st",  $WaterCountReadingValueCurrent,  1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,       $WaterCalcReadingPrefix . "_CounterDayLast", $WaterCountReadingValuePrevious, 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix . "_WFRDaySum",   0, 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix . "_WFRDayCount", 0, 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,       $WaterCalcReadingPrefix . "_WFRDayMin",   0, 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,       $WaterCalcReadingPrefix . "_WFRDayMax",   0, 1);

			### Create Log entries for debugging
			Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - Reading for the first daily value was not available and therfore reading and statistics have been written";
		}
		### Find out whether the reading for the monthly start value has not been written yet 
		if(!defined(ReadingsVal($WaterCalcReadingDestinationDeviceName,  $WaterCalcReadingPrefix . "_CounterMonth1st", undef)))
		{
			### Save current water Consumption as first reading of month
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMonth1st",  $WaterCountReadingValueCurrent,  1);	
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMonthLast", $WaterCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - Reading for the first monthly value was not available and therfore reading has been written";
			}
		### Find out whether the reading for the meter reading year value has not been written yet 
		if(!defined(ReadingsVal($WaterCalcReadingDestinationDeviceName,  $WaterCalcReadingPrefix . "_CounterMeter1st", undef)))
		{	
			### Save current water Consumption as first reading of month where Water-meter is read
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMeter1st",  $WaterCountReadingValueCurrent,  1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMeterLast", $WaterCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - Reading for the first value of water meter year was not available and therfore reading has been written";
		}
		### Find out whether the reading for the yearly value has not been written yet 
		if(!defined(ReadingsVal($WaterCalcReadingDestinationDeviceName,  $WaterCalcReadingPrefix . "_CounterYear1st", undef)))
		{	
			### Save current water Consumption as first reading of the calendar year
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterYear1st",  $WaterCountReadingValueCurrent,  1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterYearLast", $WaterCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $WaterCalcName, 3, $WaterCalcName. " : WaterCalculator - Reading for the first yearly value was not available and therfore reading has been written";
		}
		
		### Extracting year, month and day as numbers
		my $WaterCountReadingTimestampPreviousRelative = time_str2num($WaterCountReadingTimestampPrevious);
		my($WaterCountReadingTimestampPreviousSec,$WaterCountReadingTimestampPreviousMin,$WaterCountReadingTimestampPreviousHour,$WaterCountReadingTimestampPreviousMday,$WaterCountReadingTimestampPreviousMon,$WaterCountReadingTimestampPreviousYear,$WaterCountReadingTimestampPreviousWday,$WaterCountReadingTimestampPreviousYday,$WaterCountReadingTimestampPreviousIsdst)	= localtime($WaterCountReadingTimestampPreviousRelative);
		my $WaterCountReadingTimestampCurrentRelative  = time_str2num($WaterCountReadingTimestampCurrent);
		my($WaterCountReadingTimestampCurrentSec,$WaterCountReadingTimestampCurrentMin,$WaterCountReadingTimestampCurrentHour,$WaterCountReadingTimestampCurrentMday,$WaterCountReadingTimestampCurrentMon,$WaterCountReadingTimestampCurrentYear,$WaterCountReadingTimestampCurrentWday,$WaterCountReadingTimestampCurrentYday,$WaterCountReadingTimestampCurrentIsdst)			= localtime($WaterCountReadingTimestampCurrentRelative);
		
		### Correct current month by one month since Unix/Linux start January with 0 instead of 1
		$WaterCountReadingTimestampCurrentMon = $WaterCountReadingTimestampCurrentMon + 1;
		
		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Reading Name                                     : " . $WaterCountReadingName;
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Previous Reading Value                           : " . $WaterCountReadingTimestampPrevious;
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Current Reading Value                            : " . $WaterCountReadingTimestampCurrent;
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Previous Reading Value                           : " . $WaterCountReadingValuePrevious;
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Current Reading Value                            : " . $WaterCountReadingValueCurrent;
		
		####### Check whether Initial readings needs to be written
		### Check whether the current value is the first one after change of day = First one after midnight
		if ($WaterCountReadingTimestampCurrentHour < $WaterCountReadingTimestampPreviousHour)
		{
			### Create Log entries for debugging
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - First reading of day detected";

			### Calculate Water Consumption of previous day ? = (Wprevious[qm] - WcurrentDay[qm]) 
			my $WaterCalcConsumptionDayLast      = ($WaterCountReadingValuePrevious - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterDay1st", "0"));
			### Calculate pure Water cost of previous day WaterCalcConsumptionDayLast * Price per qm
			my $WaterCalcConsumptionCostDayLast  = $WaterCalcConsumptionDayLast * $attr{$WaterCalcName}{WaterPricePerCubic};
			### Reload last flow Value
			my $WaterCalcWFRCurrent = ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_WFRCurrent", "0");
			
			### Save Water pure cost of previous day, current water Consumption as first reading of day = first after midnight and reset min, max value, value counter and value sum
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,        $WaterCalcReadingPrefix . "_ConsumptionCostDayLast",  (sprintf('%.2f', ($WaterCalcConsumptionCostDayLast))), 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,        $WaterCalcReadingPrefix . "_ConsumptionDayLast",      (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionDayLast    ))), 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,        $WaterCalcReadingPrefix . "_CounterDay1st",           (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent  ))), 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,        $WaterCalcReadingPrefix . "_CounterDayLast",          (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValuePrevious ))), 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,  "." . $WaterCalcReadingPrefix . "_WFRDaySum",                0                                                   , 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,  "." . $WaterCalcReadingPrefix . "_WFRDayCount",              0                                                   , 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,        $WaterCalcReadingPrefix . "_WFRDayMin",               (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRCurrent            ))), 1);
			readingsSingleUpdate( $WaterCalcReadingDestinationDevice,        $WaterCalcReadingPrefix . "_WFRDayMax",                0                                                   , 1);
			
			
			### Check whether the current value is the first one after change of month
			if ($WaterCountReadingTimestampCurrentMday < $WaterCountReadingTimestampPreviousMday)
			{
				### Create Log entries for debugging
				Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - First reading of month detected";

				### Calculate Water Consumption of previous month ? = (Wprevious[qm] - W1stReadMonth[qm]) 
				my $WaterCalcConsumptionMonthLast     = ($WaterCountReadingValuePrevious - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterMonth1st", "0"));
				### Calculate pure Water cost of previous month WaterCalcConsumptionMonthLast * Price per qm
				my $WaterCalcConsumptionCostMonthLast = $WaterCalcConsumptionMonthLast * $attr{$WaterCalcName}{WaterPricePerCubic};
				### Save Water Consumption and pure cost of previous month
				readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionCostMonthLast",   (sprintf('%.2f', ($WaterCalcConsumptionCostMonthLast))), 1);
				readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionMonthLast",       (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionMonthLast    ))), 1);
				readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMonth1st",            (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent    ))), 1);
				readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMonthLast",           (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValuePrevious   ))), 1);

				
				### Check whether the current value is the first one of the meter-reading month
				if ($WaterCountReadingTimestampCurrentMon eq $attr{$WaterCalcName}{MonthOfAnnualReading})
				{
					### Create Log entries for debugging
					Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - First reading of month for meter reading detected";
					Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Current month is                  : " . $WaterCountReadingTimestampCurrentMon;
					Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Attribute MonthOfAnnualReading is : " . $attr{$WaterCalcName}{MonthOfAnnualReading};
					Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Counter1stMeter  is               : " . $WaterCountReadingValueCurrent;
					Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - CounterLastMeter is               : " . $WaterCountReadingValuePrevious;
					
					### Calculate Water Consumption of previous meter reading year ? = (Wprevious[qm] - WcurrentMeter[qm])
					my $WaterCalcConsumptionMeterLast = ($WaterCountReadingValuePrevious - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterMeter1st", "0"));
					### Calculate pure Water cost of previous meter reading year ? = WaterCalcConsumptionMeterLast * Price per qm
					my $WaterCalcConsumptionCostMeterLast = $WaterCalcConsumptionMeterLast * $attr{$WaterCalcName}{WaterPricePerCubic};
					
					### Save Water Consumption and pure cost of previous meter year
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionCostMeterLast", (sprintf('%.2f', ($WaterCalcConsumptionCostMeterLast ))), 1);
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionMeterLast",     (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionMeterLast     ))), 1);
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMeter1st",          (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent     ))), 1);
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterMeterLast",         (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValuePrevious    ))), 1);
				}

				### Check whether the current value is the first one of the calendar year
				if ($WaterCountReadingTimestampCurrentYear > $WaterCountReadingTimestampPreviousYear)
				{
					### Create Log entries for debugging
					Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - First reading of calendar year detected";

					### Calculate Water Consumption of previous calendar year ? = (Wcurrent[qm] - WcurrentYear[qm])
					my $WaterCalcConsumptionYearLast = ($WaterCountReadingValuePrevious - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterYear1st", "0"));
					### Calculate pure Water cost of previous calendar year ? = WaterCalcConsumptionYearLast * Price per qm
					my $WaterCalcConsumptionCostYearLast = $WaterCalcConsumptionYearLast * $attr{$WaterCalcName}{WaterPricePerCubic};

					### Save Water Consumption and pure cost of previous calendar year
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionCostYearLast", (sprintf('%.2f', ($WaterCalcConsumptionCostYearLast   ))), 1);
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionYearLast",     (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionYearLast       ))), 1);
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterYear1st",          (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent      ))), 1);
					readingsSingleUpdate( $WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterYearLast",         (sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValuePrevious     ))), 1);
				}
			}
		}
		
		###### Do calculations
		### Calculate DtCurrent (time difference) of previous and current timestamp / [s]
		my $WaterCountReadingTimestampDelta = $WaterCountReadingTimestampCurrentRelative - $WaterCountReadingTimestampPreviousRelative;
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCountReadingTimestampDelta            : " . $WaterCountReadingTimestampDelta . " s";

		### Continue with calculations only if time difference is larger than 10 seconds to avoid "Illegal division by zero" and erroneous due to small values for divisor
		if ($WaterCountReadingTimestampDelta > 10)
		{
			### Calculate water consumption (water consumption difference) of previous and current value / [qm]
			my $WaterCountReadingValueDelta = sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent )) - sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValuePrevious));
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCountReadingValueDelta                : " . $WaterCountReadingValueDelta;

			### Calculate Current water flow rate WFR = DV/Dt[qm/s] * 60[s/min] * 1000 [qm --> l] * WFRUnitFactor
			my $WaterCalcWFRCurrent    = ($WaterCountReadingValueDelta / $WaterCountReadingTimestampDelta) * 60 * 1000 * $WaterCalcDev->{system}{WFRUnitFactor};
			
			### Calculate daily sum of water flow measurements "SWFR" and measurement counts "n" and then calculate average water low rate "WFRaverage = SWFR/n"
			my $WaterCalcWFRDaySum     = ReadingsVal($WaterCalcReadingDestinationDeviceName, "." . $WaterCalcReadingPrefix . "_WFRDaySum",   "0") + $WaterCalcWFRCurrent;
			my $WaterCalcWFRDayCount   = ReadingsVal($WaterCalcReadingDestinationDeviceName, "." . $WaterCalcReadingPrefix . "_WFRDayCount", "0") + 1;
			my $WaterCalcWFRDayAverage = $WaterCalcWFRDaySum / $WaterCalcWFRDayCount;
			
			### Calculate consumed water of current  day   V = (Vcurrent[qm] - V1stReadDay[qm])   
			my $WaterCalcConsumptionDay       = ($WaterCountReadingValueCurrent - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterDay1st", "0"));

			### Calculate consumed water of current  month V = (Vcurrent[qm] - V1stReadMonth[qm]) 
			my $WaterCalcConsumptionMonth     = ($WaterCountReadingValueCurrent - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterMonth1st", "0"));

			### Calculate consumed water of current   year V = (Vcurrent[qm] - V1stReadYear[qm])  
			my $WaterCalcConsumptionYear      = ($WaterCountReadingValueCurrent - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterYear1st", "0"));

			### Calculate consumed water of Water-meter year V = (Vcurrent[qm] - V1stReadMeter[qm]) 
			my $WaterCalcConsumptionMeter     = ($WaterCountReadingValueCurrent - ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_CounterMeter1st", "0"));

			### Calculate pure Water cost since midnight
			my $WaterCalcConsumptionCostDay = $WaterCalcConsumptionDay * $attr{$WaterCalcName}{WaterPricePerCubic};

			### Calculate pure Water cost since first day of month
			my $WaterCalcConsumptionCostMonth = $WaterCalcConsumptionMonth * $attr{$WaterCalcName}{WaterPricePerCubic};
			
			### Calculate pure Water cost since first day of calendar year
			my $WaterCalcConsumptionCostYear  = $WaterCalcConsumptionYear * $attr{$WaterCalcName}{WaterPricePerCubic};
			
			### Calculate pure Water cost since first day of water meter reading year
			my $WaterCalcConsumptionCostMeter = $WaterCalcConsumptionMeter * $attr{$WaterCalcName}{WaterPricePerCubic};
			
			### Calculate the payment month since the year of water meter reading started
			my $WaterCalcMeterYearMonth=0;
			if (($WaterCountReadingTimestampCurrentMon - $attr{$WaterCalcName}{MonthOfAnnualReading} + 1) < 1)
			{
				$WaterCalcMeterYearMonth  = 13 + $WaterCountReadingTimestampCurrentMon  - $attr{$WaterCalcName}{MonthOfAnnualReading};
			}
			else
			{
				$WaterCalcMeterYearMonth  =  1 + $WaterCountReadingTimestampCurrentMon  - $attr{$WaterCalcName}{MonthOfAnnualReading};
			}
			
			### Calculate reserves at Water supplier based on monthly advance payments within year of water meter reading 
			my $WaterCalcReserves        = ($WaterCalcMeterYearMonth * $attr{$WaterCalcName}{MonthlyPayment}) - ($attr{$WaterCalcName}{BasicPricePerAnnum} / 12 * $WaterCalcMeterYearMonth) - $WaterCalcConsumptionCostMeter;

			### Create Log entries for debugging		
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - _______Finance________________________________________";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Monthly Payment                         : " . $attr{$WaterCalcName}{MonthlyPayment}             . " " . $attr{$WaterCalcName}{Currency};
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Basic price per annum                   : " . $attr{$WaterCalcName}{BasicPricePerAnnum}         . " " . $attr{$WaterCalcName}{Currency};
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcConsumptionCostMeter           : " . sprintf('%.2f', ($WaterCalcConsumptionCostMeter)) . " " . $attr{$WaterCalcName}{Currency};
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcReserves                       : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcReserves))             . " " . $attr{$WaterCalcName}{Currency};

			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - _______Times__________________________________________";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcMeterYearMonth                 : " . $WaterCalcMeterYearMonth;
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - Current Month                           : " . $WaterCountReadingTimestampCurrentMon;

			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - _______Consumption_________________________________________";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcConsumptionDay                 : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionDay))       . " qm";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcConsumptionMonth               : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionMonth))     . " qm";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcConsumptionYear                : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionYear))      . " qm";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcConsumptionMeter               : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionMeter))     . " qm";

			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - _______flow___________________________________________";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcWFRCurrent                     : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRCurrent))    . " l_min";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcWFRDayMin                      : " . ReadingsVal( $WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_WFRDayMin", 0) . " l_min";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcWFRDayAverage                  : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRDayAverage)) . " l_min";
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCalcWFRDayMax                      : " . ReadingsVal( $WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_WFRDayMax", 0) . " l_min";

			###### Write readings to WaterCalc device
			### Initialize Bulkupdate
			readingsBeginUpdate($WaterCalcReadingDestinationDevice);

			### Write consumed water Consumption (DV) since last measurement
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix . "_LastDV",      sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueDelta)));

			### Write timelap (Dt) since last measurement
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix . "_LastDt",      sprintf('%.0f', ($WaterCountReadingTimestampDelta)));
		
			### Write current flow = average flow over last measurement period
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_WFRCurrent",        sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRCurrent)));
			
			### Write daily   flow = average flow since midnight
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_WFRDayAver",        sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRDayAverage)));
			
			### Write flow measurement sum since midnight for average calculation
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix . "_WFRDaySum",   sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRDaySum)));
			
			### Write flow measurement counts since midnight for average calculation
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, "." . $WaterCalcReadingPrefix . "_WFRDayCount", sprintf('%.0f', ($WaterCalcWFRDayCount)));
			
			### Detect new daily minimum flow value and write to reading
			if (ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_WFRDayMin", 0) > $WaterCalcWFRCurrent)
			{
				### Write new minimum flow value
				readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_WFRDayMin",     sprintf('%.0f', ($WaterCalcWFRCurrent)));
				
				### Create Log entries for debugging
				Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - New daily minimum flow value detected   : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRCurrent));
			}
			
			### Detect new daily maximum flow value and write to reading
			if (ReadingsVal($WaterCalcReadingDestinationDeviceName, $WaterCalcReadingPrefix . "_WFRDayMax", 0) < $WaterCalcWFRCurrent)
			{
				### Write new maximum flow value
				readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_WFRDayMax",   sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRCurrent)));
				
				### Create Log entries for debugging
				Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - New daily maximum flow value detected   : " . sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcWFRCurrent));
			}
			
			### Write Consumption consumption since midnight
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionDay",         sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionDay)));
			
			### Write Consumption consumption since beginning of month
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionMonth",       sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionMonth)));

			### Write Consumption consumption since beginning of year
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionYear",        sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionYear)));
			
			### Write Consumption consumption since last meter reading
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionMeter",       sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcConsumptionMeter)));
			
			### Write pure Consumption costs since midnight
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionCostDay",     sprintf('%.2f', ($WaterCalcConsumptionCostDay)));
			
			### Write pure Consumption costs since beginning of month
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionCostMonth",   sprintf('%.2f', ($WaterCalcConsumptionCostMonth)));
			
			### Write pure Consumption costs since beginning of calendar year
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionCostYear",    sprintf('%.2f', ($WaterCalcConsumptionCostYear)));
			
			### Write pure Consumption costs since beginning of year of water meter reading
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_ConsumptionCostMeter",   sprintf('%.2f', ($WaterCalcConsumptionCostMeter)));

			### Write reserves at Water supplier based on monthly advance payments within year of water meter reading
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_FinanceReserve",    sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCalcReserves)));

			### Write current meter reading as sshown on the mechanical meter
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_CounterCurrent",    sprintf($WaterCalcDev->{system}{DecimalPlace}, ($WaterCountReadingValueCurrent)));
			
			### Write months since last meter reading
			readingsBulkUpdate($WaterCalcReadingDestinationDevice, $WaterCalcReadingPrefix . "_MonthMeterReading", sprintf('%.0f', ($WaterCalcMeterYearMonth)));

			### Finish and execute Bulkupdate
			readingsEndUpdate($WaterCalcReadingDestinationDevice, 1);
		}
		else
		{
			### Create Log entries for debugging
			Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - WaterCountReadingTimestampDelta = $WaterCountReadingTimestampDelta. Calculations skipped!";
		}
		
		### Create Log entries for debugging
		Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator End_________________________________________________________________________________________________________________________________";
	}
		
	### If readings exist, update list of available readings
	if($WaterCalcDev->{READINGS}) 
	{
		### Copy readings in list of available "gets" and "sets"
		%{$WaterCalcDev->{helper}{gets}} = %{$WaterCalcDev->{READINGS}};
		%{$WaterCalcDev->{helper}{sets}} = %{$WaterCalcDev->{READINGS}};

		### Create Log entries for debugging
		#Log3 $WaterCalcName, 5, $WaterCalcName. " : WaterCalculator - notify x_sets list: " . join(" ", (keys %{$WaterCalcDev->{helper}{sets}}));
	}
	
	return undef;
}
####END####### Calculate water meter values on changed events ####################################################END#####
1;


###START###### Description for fhem commandref ################################################################START####
=pod

=item helper
=item summary    Calculates the water consumption and costs
=item summary_DE Berechnet den Wasserverbrauch und verbundene Kosten

=begin html

<a name="WaterCalculator"></a>
<h3>WaterCalculator</h3>
<ul>
<table>
	<tr>
		<td>
			The WaterCalculator Module calculates the water consumption and costs of one or more water meters.<BR>
			It is not a counter module itself but it requires a regular expression (regex or regexp) in order to know where to retrieve the counting ticks of one or more mechanical or electronic water meter.<BR>
			<BR>
			<BR>
			<FONT COLOR="#FF0000">The function of the sub-counter for garden water has not been implemented yet. Therefore the sewage water cost needs to be taken into account.</FONT>
			<BR>
			As soon the module has been defined within the fhem.cfg, the module reacts on every event of the specified counter like myOWDEVICE:counter.* etc.<BR>
			<BR>
			The WaterCalculator module provides several current, historical, statistical values around with respect to one or more water meter and creates respective readings.<BR>
			<BR>
			To avoid waiting for max. 12 months to have realistic values, the readings <BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st</code>,<BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st</code>,<BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st</code> and<BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st</code><BR>
			must be corrected with real values by using the <code>setreading</code> - command.<BR>
			These real values may be found on the last water bill. Otherwise it will take 24h for the daily, 30days for the monthly and up to 12 month for the yearly values to become realistic.<BR>
			<BR>
			Intervalls smaller than 10s will be discarded to avoid peaks due to fhem blockages (e.g. DbLog - reducelog).
			<BR>
		</td>
	</tr>
</table>
  
<table><tr><td><a name="WaterCalculatorDefine"></a><b>Define</b></td></tr></table>
<table><tr><td><ul><code>define &lt;name&gt; WaterCalculator &lt;regex&gt;</code></ul></td></tr></table>
<ul><ul>
	<table>
		<tr><td><code>&lt;name&gt;</code> : </td><td>The name of the calculation device. (E.g.: "myWaterCalculator")</td></tr>
		<tr><td><code>&lt;regex&gt;</code> : </td><td>A valid regular expression (also known as regex or regexp) of the event where the counter can be found</td></tr>
	</table>
</ul></ul>
<table><tr><td><ul>Example: <code>define myWaterCalculator WaterCalculator myWaterCounter:countersA.*</code></ul></td></tr></table>
<BR>
<table>
	<tr><td><a name="WaterCalculatorSet"></a><b>Set</b></td></tr>
	<tr><td>
		<ul>
				The set - function sets individual values for example to correct values after power loss etc.<BR>
				The set - function works only for readings which have been stored in the CalculatorDevice.<BR>
				The Readings being stored in the Counter - Device need to be changed individially with the <code>set</code> - command.<BR>
		</ul>
	</td></tr>
</table>
<BR>
<table>
	<tr><td><a name="WaterCalculatorGet"></a><b>Get</b></td></tr>
	<tr><td>
		<ul>
				The get - function just returns the individual value of the reading.<BR>
				The get - function works only for readings which have been stored in the CalculatorDevice.<BR>
				The Readings being stored in the Counter - Device need to be read individially with  <code>get</code> - command.<BR>
	</ul>
	</td></tr>
</table>
<BR>
<table>
	<tr><td><a name="WaterCalculatorAttr"></a><b>Attributes</b></td></tr>
	<tr><td>
		<ul>
				If the below mentioned attributes have not been pre-defined completly beforehand, the program will create the WaterCalculator specific attributes with default values.<BR>
				In addition the global attributes e.g. <a href="#room">room</a> can be used.<BR>
		</ul>
	</td></tr>
</table>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>BasicPricePerAnnum</code> : </li></td><td>	A valid float number for basic annual fee in the chosen currency for the water supply to the home.<BR>
																			The value is provided by your local water supplier and is shown on your water bill.<BR>
																			For UK and US users it may known under "standing charge". Please make sure it is based on one year!<BR>
																			The default value is 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>Currency</code> : </li></td><td>	One of the pre-defined list of currency symbols [&#8364;,&#163;,&#36;].<BR>
																The default value is &#8364;<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>disable</code> : </li></td><td>			Disables the current module. The module will not react on any events described in the regular expression.<BR>
																		The default value is 0 = enabled.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WaterCounterOffset</code> : </li></td><td>	A valid float number of the water Consumption difference = offset (not the difference of the counter ticks!) between the value shown on the mechanic meter for the water consumption and the calculated water consumption of the counting device.<BR>
																		The value for this offset will be calculated as follows W<sub>Offset</sub> = W<sub>Mechanical</sub> - W<sub>Module</sub><BR>
																		The default value is 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WaterCubicPerCounts</code> : </li></td><td>	A valid float number of water consumption in qm per counting ticks.<BR>
																		The value is given by the mechanical trigger of the mechanical water meter. E.g. WaterCubicPerCounts = 0.001 means each count is a thousandth of one qm (=liter).<BR>
																		The default value is 1 (= the counter is already providing qm)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WaterPricePerCubic</code> : </li></td><td>	A valid float number for water Consumption price in the chosen currency per qm.<BR>
																			<FONT COLOR="#FF0000">The sewage water cost needs to be taken into account.</FONT>
																			The value is provided by your local water supplier and is shown on your water bill.<BR>
																			The default value is 2.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthlyPayment</code> : </li></td><td>		A valid float number for monthly advance payments in the chosen currency towards the water supplier.<BR>
																			The default value is 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthOfAnnualReading</code> : </li></td><td>	A valid integer number for the month when the mechanical water meter reading is performed every year.<BR>
																			The default value is 5 (May)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>ReadingDestination</code> : </li></td><td>	One of the pre-defined list for the destination of the calculated readings: [CalculatorDevice,CounterDevice].<BR>
																			The CalculatorDevice is the device which has been created with this module.<BR>
																			The CounterDevice    is the Device which is reading the mechanical Water-meter.<BR>
																			The default value is CalculatorDevice - Therefore the readings will be written into this device.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WFRUnit</code> : </li></td><td>	        One value of the pre-defined list: l/min (liter/minute), m&sup3;/min (cubicmeter/minute), m&sup3;/h (cubicmeter/hour).<BR>
																		It defines which unit shall be used and devides the water flow rate accordingly.<BR>
																		The default value is l/min (liter/minute).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<BR>
<table>
	<tr><td><a name="WaterCalculatorReadings"></a><b>Readings</b></td></tr>
	<tr><td>
		<ul>
			As soon the device has been able to read at least 2 times the counter, it automatically will create a set of readings:<BR>
			The placeholder <code>&lt;DestinationDevice&gt;</code> is the device which has been chosen in the attribute <code>ReadingDestination</code> above. <BR> This will not appear if CalculatorDevice has been chosen.<BR>
			The placeholder <code>&lt;SourceCounterReading&gt;</code> is the reading based on the defined regular expression where the counting ticks are coming from.<BR>
		</ul>
	</td></tr>
</table>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterCurrent</code> : </li></td><td>Current indicated total water consumption as shown on mechanical water meter. Correct Offset-attribute if not identical.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st</code> : </li></td><td>The first meter reading after midnight.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDayLast</code> : </li></td><td>The last meter reading of the previous day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st</code> : </li></td><td>The first meter reading after midnight of the first day of the month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonthLast</code> : </li></td><td>The last meter reading of the previous month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st</code> : </li></td><td>The first meter reading after midnight of the first day of the month where the mechanical meter is read by the Water supplier.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeterLast</code> : </li></td><td>The last meter reading of the previous meter reading year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st</code> : </li></td><td>The first meter reading after midnight of the first day of the year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYearLast</code> : </li></td><td>The last meter reading of the previous year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostDayLast</code> : </li></td><td>Consumption costs of the last day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMeterLast</code> : </li></td><td>Consumption costs in the chosen currency of the last water meter period.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMonthLast</code> : </li></td><td>Consumption costs in the chosen currency of the last month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostYearLast</code> : </li></td><td>Consumption costs of the last calendar year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostDay</code> : </li></td><td>Consumption costs in the chosen currency since the beginning of the current day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMeter</code> : </li></td><td>Consumption costs in the chosen currency since the beginning of the month of where the last water meter reading has been performed by the Water supplier.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMonth</code> : </li></td><td>Consumption costs in the chosen currency since the beginning of the current month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostYear</code> : </li></td><td>Consumption costs in the chosen currency since the beginning of the current year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionDay</code> : </li></td><td>Consumption in qm since the beginning of the current day (midnight).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionDayLast</code> : </li></td><td>Total Consumption in qm of the last day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMeter</code> : </li></td><td>Consumption in qm since the beginning of the month of where the last Water-meter reading has been performed by the Water supplier.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMeterLast</code> : </li></td><td>Total Consumption in qm of the last Water-meter reading period.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMonth</code> : </li></td><td>Consumption in qm since the beginning of the current month (midnight of the first).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMonthLast</code> : </li></td><td>Total Consumption in qm of the last month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionYear</code> : </li></td><td>Consumption in qm since the beginning of the current year (midnight of the first).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionYearLast</code> : </li></td><td>Total Consumption in qm of the last calendar year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_FinanceReserve</code> : </li></td><td>Financial Reserve based on the advanced payments done on the first of every month towards the water supplier. With negative values, an additional payment is to be expected.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_MonthMeterReading</code> : </li></td><td>Number of month since last meter reading. The month when the reading occured is the first month = 1.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRCurrent</code> : </li></td><td>Current water flow rate. (water flow rate based on current and previous measurement.)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRDayAver</code> : </li></td><td>Average water flow rate since midnight.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRDayMax</code> : </li></td><td>Maximum water flow rate peak since midnight.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRDayMin</code> : </li></td><td>Minimum water flow rate peak since midnight.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
</ul>
=end html

=begin html_DE

<a name="WaterCalculator"></a>
<h3>WaterCalculator</h3>
<ul>
<table>
	<tr>
		<td>
			Das WaterCalculator Modul berechnet den Verbrauch an Wasser und die verbundenen Kosten von einem oder mehreren Wasserz&auml;hlern.<BR>
			<BR>
			<FONT COLOR="#FF0000">Die Funktion des sogenannten Unterwasserz&auml;hlers ist noch nicht implementiert. Daher m�ssen bei den Wasserkosten die Abwasserkosten mit einbezogen werden.</FONT>
			<BR>
			Es ist kein eigenes Z&auml;hlermodul sondern ben&ouml;tigt eine Regular Expression (regex or regexp) um das Reading mit den Z&auml;hlimpulse von einem oder mehreren Wasserz&auml;hlern zu finden.<BR>
			<BR>
			Sobald das Modul in der fhem.cfg definiert wurde, reagiert das Modul auf jedes durch das regex definierte event wie beispielsweise ein myOWDEVICE:counter.* etc.<BR>
			<BR>
			Das WaterCalculator Modul berechnet augenblickliche, historische statistische und vorhersehbare Werte von einem oder mehreren Wasserz&auml;hlern und erstellt die entsprechenden Readings.<BR>
			<BR>
			Um zu verhindern, dass man bis zu 12 Monate warten muss, bis alle Werte der Realit&auml;t entsprechen, m&uuml;ssen die Readings<BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st</code>,<BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st</code>,<BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st</code> und<BR>
			<code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st</code><BR>
			entsprechend mit dem <code>setreading</code> - Befehl korrigiert werden.<BR>
			Diese Werte findet man unter Umst&auml;nden auf der letzten Abrechnung des Wasserversorgers. Andernfalls dauert es bis zu 24h f&uuml;r die t&auml;glichen, 30 Tage f&uuml;r die monatlichen und bis zu 12 Monate f&uuml;r die j&auml;hrlichen Werte bis diese der Realit&auml;t entsprechen.<BR>
			<BR>
			<BR>
			Intervalle kleienr als 10s werden ignoriert um Spitzen zu verhindern die von Blockaden des fhem Systems hervorgerufen werden (z.B. DbLog - reducelog).
		</td>
	</tr>
</table>
  
<table>
<tr><td><a name="WaterCalculatorDefine"></a><b>Define</b></td></tr>
</table>
<table><tr><td><ul><code>define &lt;name&gt; WaterCalculator &lt;regex&gt;</code></ul></td></tr></table>
<ul><ul>
	<table>
		<tr><td><code>&lt;name&gt;</code> : </td><td>Der Name dieses Berechnungs-Device. Empfehlung: "myWaterCalculator".</td></tr>
		<tr><td><code>&lt;regex&gt;</code> : </td><td>Eine g&uuml;ltige Regular Expression (regex or regexp) von dem Event wo der Z&auml;hlerstand gefunden werden kann</td></tr>
	</table>
</ul></ul>
<table><tr><td><ul>Beispiel: <code>define myWaterCalculator WaterCalculator myWaterCounter:countersA.*</code></ul></td></tr></table>
<BR>
<table>
	<tr><td><a name="WaterCalculatorSet"></a><b>Set</b></td></tr>
	<tr><td>
		<ul>
				Die set - Funktion erlaubt individuelle Readings zu ver&auml;ndern um beispielsweise nach einem Stromausfall Werte zu korrigieren.<BR>
				Die set - Funktion funktioniert nur f&uumlr Readings welche im CalculatorDevice gespeichert wurden.<BR>
				Die Readings welche im Counter - Device gespeichert wurden, m&uumlssen individuell mit <code>set</code> - Befehl gesetzt werden.<BR>
		</ul>
	</td></tr>
</table>
<BR>
<table>
	<tr><td><a name="WaterCalculatorGet"></a><b>Get</b></td></tr>
	<tr><td>
		<ul>
				Die get - Funktion liefert nur den Wert des jeweiligen Readings zur&uuml;ck.<BR>
				Die get - Funktion funktioniert nur f&uumlr Readings welche im CalculatorDevice gespeichert wurden.<BR>
				Die Readings welche im Counter - Device gespeichert wurden, m&uumlssen individuell mit <code>get</code> - Befehl ausgelesen werden.<BR>
		</ul>
	</td></tr>
</table>
<BR>
<table>
	<tr><td><a name="WaterCalculatorAttr"></a><b>Attributes</b></td></tr>
	<tr><td>
		<ul>
				Sollten die unten ausfeg&auuml;hrten Attribute bei der Definition eines entsprechenden Ger&auml;tes nicht gesetzt sein, so werden sie vom Modul mit Standard Werten automatisch gesetzt<BR>
				Zus&auml;tzlich k&ouml;nnen die globalen Attribute wie <a href="#room">room</a> verwendet werden.<BR>
		</ul>
	</td></tr>
</table>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>BasicPricePerAnnum</code> : </li></td><td>	Eine g&uuml;ltige float Zahl f&uuml;r die j&auml;hrliche Grundgeb&uuml;hr in der gew&auml;hlten W&auml;hrung f&uuml;r die Wasser-Versorgung zum Endverbraucher.<BR>
																			Dieser Wert stammt vom Wasserversorger und steht auf der Abrechnung.<BR>
																			Der Standard Wert ist 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>Currency</code> : </li></td><td>	Eines der vordefinerten W&auml;hrungssymbole: [&#8364;,&#163;,&#36;].<BR>
																Der Standard Wert ist &#8364;<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>disable</code> : </li></td><td>	Deaktiviert das device. Das Modul wird nicht mehr auf die Events reagieren die durch die Regular Expression definiert wurde.<BR>
																Der Standard Wert ist 0 = aktiviert.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WaterCounterOffset</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r den Unterschied = Offset (Nicht der Unterschied zwischen Z&auml;hlimpulsen) zwischen dem am mechanischen Wasserz&auml;hlern und dem angezeigten Wert im Reading dieses Device.<BR>
																				Der Offset-Wert wird wie folgt ermittelt: W<sub>Offset</sub> = W<sub>Mechanisch</sub> - W<sub>Module</sub><BR>
																				Der Standard-Wert ist 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WaterCubicPerCounts</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r die Menge Kubik pro Z&auml;hlimpulsen.<BR>
																				Der Wert ist durch das mechanische Z&auml;hlwerk des Wasserz&auml;hlern vorgegeben. WaterCubicPerCounts = 0.001 bedeutet, dass jeder Z&auml;hlimpuls ein Tausendstel eines Kubik ist (=Liter).<BR>
																				Der Standard-Wert ist 1<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WaterPricePerCubic</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r den Preis pro Kubik Wasser.<BR>
																				<FONT COLOR="#FF0000">Hierbei m�ssen die Abwasserkosten mit einbezogen werden.</FONT>
																				Dieser Wert stammt vom Wasserversorger und steht auf der Abrechnung.<BR>
																				Der Standard-Wert ist 2.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthlyPayment</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r die monatlichen Abschlagszahlungen in der gew&auml;hlten W&auml;hrung an den Wasserversorger.<BR>
																		Der Standard-Wert ist 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthOfAnnualReading</code> : </li></td><td>	Eine g&uuml;ltige Ganz-Zahl f&uuml;r den Monat wenn der mechanische Wasserz&auml;hler jedes Jahr durch den Wasserversorger abgelesen wird.<BR>
																			Der Standard-Wert ist 5 (Mai)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>ReadingDestination</code> : </li></td><td>	Eines der vordefinerten Device als Ziel der errechneten Readings: [CalculatorDevice,CounterDevice].<BR>
																			Das CalculatorDevice ist das mit diesem Modul erstellte Device.<BR>
																			Das CounterDevice ist das Device von welchem der mechanische Z&auml;hler ausgelesen wird.<BR>
																			Der Standard-Wert ist CalculatorDevice.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>WFRUnit</code> : </li></td><td>	        	Ein Wert der vorgegebenen Auswahlliste: l/min (Liter/Minute), m&sup3;/min (Kubikmeter/Minute), m&sup3;/h (Kubikmeter/Stunde).<BR>
																			Es definiert welcher Einheit verwendet werden soll und teilt den Wasserdurchsatz entsprechend.<BR>
																			Der Standard-Wert ist l/min (Liter/Minute).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<BR>
<table>
	<tr><td><a name="WaterCalculatorReadings"></a><b>Readings</b></td></tr>
	<tr><td>
		<ul>
			Sobald das Device in der Lage war mindestens 2 Werte des Z&auml;hlers einzulesen, werden automatisch die entsprechenden Readings erzeugt:<BR>
			Der Platzhalter <code>&lt;DestinationDevice&gt;</code> steht f&uuml;r das Device, welches man in dem Attribut <code>ReadingDestination</code> oben festgelegt hat. Dieser Platzhalter bleibt leer, sobald man dort CalculatorDevice ausgew&auml;hlt hat.<BR>
			Der Platzhalter <code>&lt;SourceCounterReading&gt;</code> steht f&uuml;r das Reading welches mit der Regular Expression definiert wurde.<BR>
		</ul>
	</td></tr>
</table>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterCurrent</code> : </li></td><td>Aktueller Z&auml;hlerstand am mechanischen Z&auml;hler. Bei Unterschied muss das Offset-Attribut entspechend korrigiert werden.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDay1st</code> : </li></td><td>Der erste Z&auml;hlerstand des laufenden Tages seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterDayLast</code> : </li></td><td>Der letzte Z&auml;hlerstand des vorherigen Tages.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeter1st</code> : </li></td><td>Der erste Z&auml;hlerstand seit Mitternacht des ersten Tages der laufenden Ableseperiode.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMeterLast</code> : </li></td><td>Der letzte Z&auml;hlerstand seit Mitternacht des ersten Tages der vorherigen Ableseperiode.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonth1st</code> : </li></td><td>Der erste Z&auml;hlerstand seit Mitternacht des ersten Tages des laufenden Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterMonthLast</code> : </li></td><td>Der letzte Z&auml;hlerstand des vorherigen Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYear1st</code> : </li></td><td>Der erste Z&auml;hlerstand seit Mitternacht des ersten Tages des laufenden Jahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_CounterYearLast</code> : </li></td><td>Der letzte Z&auml;hlerstand des letzten Jahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostDayLast</code> : </li></td><td>Wasserkosten des letzten Tages.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMeterLast</code> : </li></td><td>Wasserkosten der letzten Ableseperiode.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMonthLast</code> : </li></td><td>Wasserkosten des letzten Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostYearLast</code> : </li></td><td>Wasserkosten des letzten Kalenderjahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostDay</code> : </li></td><td>Wasserkosten in gew&auml;hlter W&auml;hrung seit Mitternacht des laufenden Tages.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMeter</code> : </li></td><td>Wasserkosten in gew&auml;hlter W&auml;hrung seit Beginn der laufenden Ableseperiode.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostMonth</code> : </li></td><td>Wasserkosten in gew&auml;hlter W&auml;hrung seit Beginn des laufenden Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionCostYear</code> : </li></td><td>Wasserkosten in gew&auml;hlter W&auml;hrung seit Beginn des laufenden Kalenderjahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionDay</code> : </li></td><td>Wasserverbrauch seit Beginn der aktuellen Tages (Mitternacht).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionDayLast</code> : </li></td><td>Wasserverbrauch in qm des vorherigen Tages.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMeter</code> : </li></td><td>Wasserverbrauch seit Beginn der aktuellen Ableseperiode.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMeterLast</code> : </li></td><td>Wasserverbrauch in qm der vorherigen Ableseperiode.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMonth</code> : </li></td><td>Wasserverbrauch seit Beginn des aktuellen Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionMonthLast</code> : </li></td><td>Wasserverbrauch in qm des vorherigen Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionYear</code> : </li></td><td>Wasserverbrauch seit Beginn des aktuellen Kalenderjahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_ConsumptionYearLast</code> : </li></td><td>Wasserverbrauch in qm des vorherigen Kalenderjahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_FinanceReserve</code> : </li></td><td>Finanzielle Reserve basierend auf den Abschlagszahlungen die jeden Monat an den Wasserversorger gezahlt werden. Bei negativen Werten ist von einer Nachzahlung auszugehen.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_MonthMeterReading</code> : </li></td><td>Anzahl der Monate seit der letzten Z�hlerablesung. Der Monat der Z�hlerablesung ist der erste Monat = 1.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRCurrent</code> : </li></td><td>Aktueller Wasserdurchsatz. (Wasserdurchsatz basierend auf aktueller und letzter Messung)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRDayAver</code> : </li></td><td>Mittlerer Wasserdurchsatz seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRDayMax</code> : </li></td><td>Maximale Wasserdurchsatz seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_WFRDayMin</code> : </li></td><td>Minimale Wasserdurchsatz seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
</ul>
=end html_DE
=cut