# Add Turbo Targets - Add Multiple Targets of Different Types to a Turbonomic Instance

## Table of Contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Supported Target Types](#targets)
4. [Syntax](#syntax)
5. [Parameters](#parameters)
6. [Examples](#examples)

******

## Description <a name="description"></a>

This script allows you to bulk add targets in Turbonomic via the API using CSV files.  Each
target type is it's own CSV file that you provide in a subfolder.  All of the target types
require a different CSV file in order to specify the different fields required by each target type.

******

## Requirements <a name="requirements"></a>

* Turbonomic XL 8.1.x or higher

* Powershell 5.1 or greater

* targetmetadata.json file
  * This is a provided definition file that outlines the required fields for each target that is needed in order for the script to run
  * Do not edit this file

* Folder with csv files that specify the targets you wish you add

******

## Supported Target Types <a name="targets"></a>

Currently, only the following target types are supported:

      -AWS (with or without IAM Role)
      -AWS Billing (with or without IAM Role)
      -Microsoft Enterprise Agreement
      -Azure Service Principle
      -vCenter
      -Hyper-V
      -SQL Server
      -Oracle Databases

******

## Syntax <a name="syntax"></a>

```PowerShell
PS> ./add_turbo_targets.ps1 [-TurboInstance] <String> [-Username] <String> [-Password] <String> 
    [[-Credential] <PSCredential>] [[-csvFolder] <String>] [-UpdateTargets] [<CommonParameters>]
```

## Parameters <a name="parameters"></a>

```powershell
-Turbo_Instance <String>
        Hostname or IP address of the Turbonomic instance to add targets to.
        
    -Username <String>
        Username used to add targets to Turbonomic instance.  Must had administrator priviledges.
        
    -Password <String>
        Password for Username parameter.
        
    -Credential <PSCredential>
        
    -CSVFolder <String>
        Optional parameter to specify the folder that contains the csv files.  Default is csvFiles.
        
    -JSONMap <String>
        
    -UpdateTargets [<SwitchParameter>]
        Optional parameter.  If specified and target already exists, it will be updated.  
        If target does not exist, it will be added
```

## Examples <a name="examples"></a>

### Setup

Download the add_turbo_targets.ps1 and targetmetadata.json files and put them into the same directory.  
You should also create a subdirectory called "csvFiles" which will contain the CSV files with the targets to 
add.  You can see examples of how to create the CSV files in the "csvFiles" folder within the repository.

### Examples

You can run the script with no parameters and you will be prompted for the Turbo instance hostname/IP, username, and password:

```powershell
PS> ../add_turbo_targets.ps1
```

Alternatively, you can also specify all the required parameters:

```powershell
PS> ../add_turbo_targets.ps1 -TurboInstance turbo.example.com -Username administrator -Password password
```
