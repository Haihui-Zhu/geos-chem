#!/bin/bash

#SBATCH -c 8
#SBATCH -N 1
#SBATCH -t 0-00:30
#SBATCH -p REQUESTED_PARTITION
#SBATCH --mem=8000
#SBATCH --mail-type=END
#BSUB -q REQUESTED_PARTITION
#BSUB -n 8
#BSUB -W 00:30
#BSUB -R "rusage[mem=8GB] span[ptile=1] select[mem < 1TB]"
#BSUB -a 'docker(registry.gsc.wustl.edu/sleong/esm:intel-2021.1.2)'
#BSUB -o lsf-%J.txt

#------------------------------------------------------------------------------
#                  GEOS-Chem Global Chemical Transport Model                  !
#------------------------------------------------------------------------------
#BOP
#
# !MODULE: intTestCompile.sh
#
# !DESCRIPTION: Runs compilation tests on various GEOS-Chem Classic
#  run directories (interactively or using a scheduler).
#\\
#\\
# !CALLING SEQUENCE:
#  ./intTestCompile.sh        # Interactive command-line execution
#  bsub intTestCompile.sh     # Execution via LSF
#  sbatch intTestCompile.sh   # Execution via SLURM
#EOP
#------------------------------------------------------------------------------
#BOC

#============================================================================
# Global variable and function definitions
#============================================================================

# Get the long path of the integration test folder
itRoot=$(pwd -P)

# Load the user-environment and the software environment
. ~/.bashrc               > /dev/null 2>&1
. ${itRoot}/gcclassic.env > /dev/null 2>&1

# All integration tests will use debugging features
baseOptions="-DCMAKE_BUILD_TYPE=Debug -DRUNDIR='' -DINSTALLCOPY=${itRoot}/exe_files"
# Get the Git commit of the superproject and submodules
head_gcc=$(export GIT_DISCOVERY_ACROSS_FILESYSTEM=1; \
           git -C "./CodeDir" log --oneline --no-decorate -1)
head_gc=$(export GIT_DISCOVERY_ACROSS_FILESYSTEM=1; \
          git -C "./CodeDir/src/GEOS-Chem" log --oneline --no-decorate -1)
head_hco=$(export GIT_DISCOVERY_ACROSS_FILESYSTEM=1; \
           git -C "./CodeDir/src/HEMCO" log --oneline --no-decorate -1)

# Determine the scheduler from the job ID (or lack of one)
scheduler="none"
[[ "x${SLURM_JOBID}" != "x" ]] && scheduler="SLURM"
[[ "x${LSB_JOBID}"   != "x" ]] && scheduler="LSF"

if [[ "x${scheduler}" != "xSLURM" ]]; then

    #-----------------------
    # SLURM settings
    #-----------------------

    # Set OMP_NUM_THREADS to the same # of cores requested with #SBATCH -c
    export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK}

elif [[ "x${scheduler}" != "xLSF" ]]; then

    #-----------------------
    # LSF settings
    #-----------------------

    # Set OMP_NUM_THREADS to the same # of cores requested with #BSUB -n
    export OMP_NUM_THREADS=${$LSB_DJOB_NUMPROC}

else

    #-----------------------
    # Interactive settings
    #-----------------------

    # For AWS, set $OMP_NUM_THREADS to the available cores
    kernel=$(uname -r)
    [[ "x${kernel}" == "xaws" ]] && export OMP_NUM_THREADS=$(nproc)

fi

# Sanity check: Set OMP_NUM_THREADS to 6 if it is not set
# (this may happen when running interactively)
[[ "x${OMP_NUM_THREADS}" == "x" ]] && export OMP_NUM_THREADS=6

# Sanity check: Max out the OMP_STACKSIZE if it is not set
[[ "x${OMP_STACKSIZE}" == "x" ]] && export OMP_STACKSIZE=500m

#============================================================================
# Load common variables and functions for tesets
#============================================================================

# Include global variables & functions
. "${itRoot}/commonFunctionsForTests.sh"

# Count the number of tests to be done
numTests=${#EXE_GCC_BUILD_LIST[@]}

#============================================================================
# Initialize results logfile
#============================================================================

# Results logfile name
results="${itRoot}/logs/results.compile.log"
rm -f ${results}

# Print header to results log file
print_to_log "${SEP_MAJOR}"                                "${results}"
print_to_log "GEOS-Chem Classic: Compilation Test Results" "${results}"
print_to_log ""                                            "${results}"
print_to_log "GCClassic #${head_gcc}"                      "${results}"
print_to_log "GEOS-Chem #${head_gc}"                       "${results}"
print_to_log "HEMCO     #${head_hco}"                      "${results}"
print_to_log ""                                            "${results}"
print_to_log "Using ${OMP_NUM_THREADS} OpenMP threads"     "${results}"
print_to_log "Number of compilation tests: ${numTests}"    "${results}"
print_to_log "${SEP_MAJOR}"                                "${results}"

#============================================================================
# Configure and compile code in each GEOS_Chem run directory
#============================================================================
print_to_log " "                   "${results}"
print_to_log "Compiliation tests:" "${results}"
print_to_log "${SEP_MINOR}"        "${results}"

# Change to the top-level build directory
cd "${itRoot}"

# Keep track of the number of tests that passed & failed
let passed=0
let failed=0
let remain=${numTests}

# Loop over build directories
for dir in ${EXE_GCC_BUILD_LIST[@]}; do

    # Define build directory
    buildDir="${itRoot}/build/${dir}"

    # Define log file
    log="${itRoot}/logs/compile.${dir}.log"
    rm -f "${log}"

    # Configure and build GEOS-Chem Classic source code
    # and increment pass/fail/remain counters
    build_model "gcclassic"      "${itRoot}" "${buildDir}" \
                "${baseOptions}" "${log}"    "${results}"
    if [[ $? -eq 0 ]]; then
        let passed++
    else
        let failed++
    fi
    let remain--
done

#============================================================================
# Check the number of simulations that have passed
#============================================================================

# Print summary to log
print_to_log " "                                           "${results}"
print_to_log "Summary of compilation test results:"        "${results}"
print_to_log "${SEP_MINOR}"                                "${results}"
print_to_log "Complilation tests passed:        ${passed}" "${results}"
print_to_log "Complilation tests failed:        ${failed}" "${results}"
print_to_log "Complilation tests not completed: ${remain}" "${results}"

# Check for success
if [[ "x${passed}" == "x${numTests}" ]]; then

    #--------------------------
    # Successful compilation
    #--------------------------
    print_to_log ""                                        "${results}"
    print_to_log "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%" "${results}"
    print_to_log "%%%  All compilation tests passed!  %%%" "${results}"
    print_to_log "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%" "${results}"

    # Start the interactive execution test script upon successful finish
    if [[ "x${scheduler}" == "xnone" ]]; then
        echo ""
        echo "Compilation tests finished!"
        ./intTestExecute.sh &
    fi

else

    #---------------------------
    # Unsuccessful compilation
    #---------------------------
    if [[ "x${scheduler}" == "xnone" ]]; then
       echo ""
       echo "Compilation tests failed!  Exiting..."
    fi
fi

#============================================================================
# Cleanup and quit
#============================================================================

# Free local variables
unset baseOptions
unset failed
unset dir
unset head_gcc
unset head_gc
unset head_hco
unset itRoot
unset kernel
unset log
unset numTests
unset passed
unset remain
unset results
unset scheduler

# Free imported variables
unset FILL
unset SEP_MAJOR
unset SEP_MINOR
unset CMP_PASS_STR
unset CMP_FAIL_STR
unset EXE_PASS_STR
unset EXE_FAIL_STR
#EOC
