#!/bin/bash

export ANTS_RANDOM_SEED=1
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=8

############################################################
# Help                                                     #
############################################################
Help()
{
   # Display Help
   echo "Add description of the script functions here."
   echo
   echo "Syntax: preprocessing_Rats [-qc|h]"
   echo "options:"
   echo "-q    save screeshots in the QC root folder using -q "
   echo "-h     Print this Help."
   echo "-s 'BL 1mpi 2mpi 4mpi 8mpi' sessions"
   echo "-t '1mpi' target"
}

QC=False

while getopts 'h:q:s:t:' flag
do
    case "${flag}" in
        h)
          Help
          exit 1;;
        q)
          QC=True;;
        s)
          sessions=$OPTARG;;
        t)
          session_target=$OPTARG;;
    esac
done

echo "Quality check is " $QC
#sessions=(BL 1mpi 2mpi 4mpi 8mpi)

modalities=(R2star_MTOFF_FA06 MPF_6_24 T1map_6_24 QSM MTOFF_FA06)

# MVtemp_template0 -> R2star
# MVtemp_template1 -> MPF6_24
# MVtemp_template2 -> T1map
# MVtemp_template3 -> QSM
anat_template0=MMtemplate/reorient/MVtemp_template0.nii.gz
anat_template1=MMtemplate/reorient/MVtemp_template1.nii.gz
anat_template2=MMtemplate/reorient/MVtemp_template2.nii.gz
anat_template3=MMtemplate/reorient/MVtemp_template3.nii.gz
brainmask_template=MMtemplate/segmentation/FISCHER_BrainMask.nii.gz


#correct header for Segm_1mpi
WarpImageMultiTransform 3 Segm_1mpi.nii.gz Segm_1mpi_ro.nii.gz -R MVtemp_template1.nii.gz --reslice-by-header --use-NN
fslswapdim Segm_1mpi_ro.nii.gz  x -y z MMtemplate/reorient/Segm_1mpi.nii.gz
fslcpgeom  MMtemplate/reorient/MVtemp_template1.nii.gz MMtemplate/reorient/Segm_1mpi.nii.gz
fslswapdim MMtemplate/reorient/Segm_1mpi.nii.gz -x y z MMtemplate/reorient/Segm_1mpi_contro.nii.gz
fslcpgeom  MMtemplate/reorient/Segm_1mpi.nii.gz MMtemplate/reorient/Segm_1mpi_contro.nii.gz

#mkdir QC

for ses in ${sessions[*]}
  do
    echo $ses
    mkdir $ses/reorient

    for mod in ${modalities[*]}
      do
        echo $mod
        fslchfiletype NIFTI_GZ $ses/${mod}*

        fslswapdim $ses/${mod}.nii.gz x -y z $ses/reorient/${mod}.nii.gz

        DenoiseImage -d 3 -i $ses/reorient/${mod}.nii.gz -o $ses/reorient/${mod}.nii.gz -r 3x3x3 -v
        DenoiseImage -d 3 -i $ses/reorient/${mod}.nii.gz -o $ses/reorient/${mod}.nii.gz -r 3x3x3 -n Rician -v

        fslcpgeom  $ses/${mod}.nii.gz $ses/reorient/${mod}.nii.gz
        CopyImageHeaderInformation $anat_template0 $ses/reorient/${mod}.nii.gz $ses/reorient/${mod}.nii.gz 1 0 0 0

      done

    mkdir $ses/registration

    fast_reg=$ses/registration/template_2_subj

    anat_subj0=$ses/reorient/${modalities[0]}.nii.gz
    anat_subj1=$ses/reorient/${modalities[1]}.nii.gz
    anat_subj2=$ses/reorient/${modalities[2]}.nii.gz
    anat_subj3=$ses/reorient/${modalities[3]}.nii.gz

    # fast Single Contrast (MPF_6_24 only) registration template -> subject
    antsRegistration --verbose 1 --dimensionality 3 --float 0 --collapse-output-transforms 1 --random-seed $ANTS_RANDOM_SEED \
      --output $fast_reg \
      --interpolation Linear --use-histogram-matching 0 --winsorize-image-intensities [ 0.005,0.995 ] \
      --transform Rigid[0.1] \
      --metric CC[ $anat_subj1 , $anat_template1 ,1,1,None,0.25,0] \
      --convergence [ 1000x500x250x0,1e-6,10 ] --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox \
      --transform Affine[ 0.1 ] \
      --metric CC[ $anat_subj1 , $anat_template1 ,1,1,None,0.25,0] \
      --convergence [ 1000x500x250x0,1e-6,10 ] --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox \

    #--metric MI[ $anat_subj1 , $anat_template1 ,1,32,Regular,0.25 ]  \
    #--metric MI[ $anat_subj1 , $anat_template1 ,1,32,Regular,0.25 ] \

    mkdir $ses/segmentation
    antsApplyTransforms -d 3 -i $brainmask_template -r $anat_subj1 -o $ses/segmentation/brainmask.nii.gz -t  ${fast_reg}0GenericAffine.mat

    if [ $QC = True ]
    then
      location=`fslstats $ses/segmentation/brainmask.nii.gz -c`
      atlas=$ses/segmentation/brainmask.nii.gz
      anat=$ses/reorient/MPF_6_24.nii.gz

      fsleyes render --outfile QC/brainmask_${ses}_${ANTS_RANDOM_SEED}.png --size 800 600 --scene ortho --worldLoc $location --displaySpace $anat \
      --xcentre  0.00000  0.00000 --ycentre  0.00000  0.00000 --zcentre  0.00000  0.00000 --xzoom 100.0 --yzoom 100.0 --zzoom 100.0 \
      --showLocation no --layout horizontal --cursorWidth 1.0 --bgColour 0.0 0.0 0.0 --fgColour 1.0 1.0 1.0 --cursorColour 0.0 1.0 0.0 \
      --colourBarLocation top --colourBarLabelSide top-left --colourBarSize 100.0 --labelSize 12 --performance 3 \
      $anat --name "MPF_6_24" --overlayType volume --alpha 100.0 --brightness 49.75000000000001 --contrast 49.90029860765409 --cmap greyscale \
      --negativeCmap greyscale --displayRange 0.0 0.23307692423462867 --clippingRange 0.0 0.23307692423462867 --modulateRange 0.0 0.23076923191547394 \
      --gamma 0.0 --cmapResolution 256 --interpolation none --numSteps 150 --blendFactor 0.1 --smoothing 0 --resolution 100 --numInnerSteps 10 \
      --clipMode intersection --volume 0 $atlas --name "brainmask" --overlayType label --alpha 100.0 \
      --brightness 49.75000000000001 --contrast 49.90029860765409 --lut random --outline --outlineWidth 1 --volume 0

    fi


  done

#######################################
#template subject-specific construction
#######################################

session_target=1mpi
mkdir $session_target/warped

anat_target=()
for i in {0..4}
do
  anat_target+=($session_target/reorient/${modalities[$i]}.nii.gz)
done

brainmask_target=$session_target/segmentation/brainmask.nii.gz

for ses in ${sessions[*]}
  do
    echo $ses $session_target
   if [[ "${ses}" != "${session_target}" ]];
    then
      echo $ses
      echo $ses $session_target
      SS_reg=$session_target/registration/subj_2_subj_$ses
      anat_source=()
      for i in {0..4}
      do
        anat_source+=($ses/reorient/${modalities[$i]}.nii.gz)
      done
      brainmask_source=$ses/segmentation/brainmask.nii.gz

      antsRegistration --verbose 1 --dimensionality 3 --float 0 --collapse-output-transforms 1 --random-seed $ANTS_RANDOM_SEED \
      --output $SS_reg --interpolation Linear --use-histogram-matching 0 --winsorize-image-intensities [ 0.005,0.995 ] \
      -x [ $brainmask_target ,$brainmask_source ] --initial-moving-transform [ ${anat_target[4]},${anat_source[4]},1 ] \
      --transform Rigid[ 0.1 ] \
      --metric CC[ ${anat_target[4]},${anat_source[4]},1,2 ] \
      --convergence [ 1000x500x250x100,1e-6,10 ] --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox \
      --transform Affine[ 0.1 ] \
      --metric CC[ ${anat_target[4]},${anat_source[4]},1,2 ] \
      --convergence [ 1000x500x250x100,1e-6,10 ] --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox \
      --transform SyN[ 0.1,3,0 ] \
      --metric CC[ ${anat_target[4]},${anat_source[4]},1,2 ] \
      --convergence [50x20,1e-6,10 ] --shrink-factors 2x1 --smoothing-sigmas 1x0vox

      #      --metric MI[ ${anat_target[4]},${anat_source[4]},1,32,Regular,0.25 ] \

      for i in {0..4}
      do
        echo ${anat_source[$i]}
        anat_warped=$session_target/warped/${modalities[$i]}_${ses}.nii.gz
        antsApplyTransforms -d 3 -i ${anat_source[$i]} -r ${anat_target[1]} -o $anat_warped  -t ${SS_reg}1Warp.nii.gz -t  ${SS_reg}0GenericAffine.mat
      done

    fi

  done

  for i in {0..4}
  do
    AverageImages 3 $session_target/warped/${modalities[$i]}_mean.nii.gz 0 ${anat_target[$i]} $session_target/warped/${modalities[$i]}_*.nii.gz
    echo "mean Templage SS done !"
  done

  ##########################################################################
  #average template to template subject-specific MM registration (to session targeted)
  ##########################################################################

  anat_target_mean=()
  for i in {0..4}
  do
    anat_target_mean+=($session_target/warped/${modalities[$i]}_mean.nii.gz)
  done

  TemplMM_reg=$session_target/registration/template_2_subj_MM

  antsRegistration --verbose 1 --dimensionality 3 --float 0 --collapse-output-transforms 1 --random-seed $ANTS_RANDOM_SEED \
  --output $TemplMM_reg --interpolation Linear --use-histogram-matching 0 --winsorize-image-intensities [ 0.005,0.995 ] \
  -x [ $brainmask_target ,$brainmask_template ] --initial-moving-transform [ ${anat_target[1]},${anat_template1},1 ] \
  --transform Rigid[ 0.1 ] \
  --metric CC[ ${anat_target_mean[0]},${anat_template0},1,2,None,0.25 ] \
  --convergence [ 1000x500x250x100,1e-6,10 ] --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox \
  --transform Affine[ 0.1 ] \
  --metric CC[ ${anat_target_mean[0]},${anat_template0},1,2,None,0.25 ] \
  --convergence [ 1000x500x250x100,1e-6,10 ] --shrink-factors 8x4x2x1 --smoothing-sigmas 3x2x1x0vox \
  --transform SyN[ 0.1,3,0 ] \
  --metric CC[ ${anat_target_mean[0]},${anat_template0},1,2,None,0.25 ] \
  --metric CC[ ${anat_target_mean[1]},${anat_template1},1,2,None,0.25 ] \
  --metric CC[ ${anat_target_mean[2]},${anat_template2},1,2,None,0.25 ] \
  --convergence [50x20x10,1e-6,10 ] --shrink-factors 4x2x1 --smoothing-sigmas 2x1x0vox

  segmentation_mask_SN_L=MMtemplate/segmentation/FISCHER_SN_Left_sym.nii.gz
  segmentation_mask_SN_R=MMtemplate/segmentation/FISCHER_SN_Right_sym.nii.gz

  mask_SN_L_warped=$session_target/segmentation/SN_Left.nii.gz
  mask_SN_R_warped=$session_target/segmentation/SN_Right.nii.gz

  antsApplyTransforms -d 3 -i ${segmentation_mask_SN_L} -r ${anat_target_mean[1]} -o $mask_SN_L_warped  -t ${TemplMM_reg}1Warp.nii.gz -t  ${TemplMM_reg}0GenericAffine.mat -n NearestNeighbor
  antsApplyTransforms -d 3 -i ${segmentation_mask_SN_R} -r ${anat_target_mean[1]} -o $mask_SN_R_warped  -t ${TemplMM_reg}1Warp.nii.gz -t  ${TemplMM_reg}0GenericAffine.mat -n NearestNeighbor


  ##########################################################################
  #Warp template subject-specific MM registration to all subject's sessions
  ##########################################################################

  for ses in ${sessions[*]}
    do
      echo $ses $session_target

      echo $ses
      echo $ses $session_target
      SS_reg=$session_target/registration/subj_2_subj_$ses
      TemplMM_reg=$session_target/registration/template_2_subj_MM

      segmentation_mask_SN_L=MMtemplate/segmentation/FISCHER_SN_Left_sym.nii.gz
      segmentation_mask_SN_R=MMtemplate/segmentation/FISCHER_SN_Right_sym.nii.gz

      mask_SN_L_warped=${ses}/segmentation/SN_Left.nii.gz
      mask_SN_R_warped=${ses}/segmentation/SN_Right.nii.gz

      anat_source=$ses/reorient/${modalities[1]}.nii.gz
      brainmask_source=$ses/segmentation/brainmask.nii.gz

      if [[ "${ses}" != "${session_target}" ]];
      then
        all_transfos="-t ${SS_reg}1InverseWarp.nii.gz -t [${SS_reg}0GenericAffine.mat , 1] -t ${TemplMM_reg}1Warp.nii.gz -t ${TemplMM_reg}0GenericAffine.mat"
      else
        all_transfos="-t ${TemplMM_reg}1Warp.nii.gz -t ${TemplMM_reg}0GenericAffine.mat"
      fi

      antsApplyTransforms -d 3 -i ${segmentation_mask_SN_L} -r ${anat_source} -o $mask_SN_L_warped $all_transfos -v 1 -n NearestNeighbor
      antsApplyTransforms -d 3 -i ${segmentation_mask_SN_R} -r ${anat_source} -o $mask_SN_R_warped $all_transfos -v 1 -n NearestNeighbor

      segmentation_manual_L=MMtemplate/reorient/Segm_1mpi.nii.gz
      segmentation_auto_R=MMtemplate/reorient/Segm_1mpi_contro.nii.gz
      mask_Manual_L_warped=${ses}/segmentation/Manual_Left_testv2.nii.gz
      mask_Auto_R_warped=${ses}/segmentation/Auto_Right_test_v2.nii.gz

      antsApplyTransforms -d 3 -i ${segmentation_manual_L} -r ${anat_source} -o $mask_Manual_L_warped  $all_transfos -v 1 -n NearestNeighbor
      antsApplyTransforms -d 3 -i ${segmentation_auto_R} -r ${anat_source} -o $mask_Auto_R_warped $all_transfos -v 1 -n NearestNeighbor

      if [ $QC = True ]
      then
        location=`fslstats ${mask_Manual_L_warped} -c`
        anat=$ses/reorient/MPF_6_24.nii.gz

        fsleyes render --outfile QC/SN_$ses.png --size 800 600 --scene ortho --worldLoc $location --displaySpace $anat \
        --xcentre  0.00000  0.00000 --ycentre  0.00000  0.00000 --zcentre  0.00000  0.00000 --xzoom 100.0 --yzoom 100.0 --zzoom 100.0 \
        --showLocation no --layout horizontal --cursorWidth 1.0 --bgColour 0.0 0.0 0.0 --fgColour 1.0 1.0 1.0 --cursorColour 0.0 1.0 0.0 \
        --colourBarLocation top --colourBarLabelSide top-left --colourBarSize 100.0 --labelSize 12 --performance 3 \
        $anat --name "MPF_6_24" --overlayType volume --alpha 100.0 --brightness 49.75000000000001 --contrast 49.90029860765409 --cmap greyscale \
        --negativeCmap greyscale --displayRange 0.0 0.23307692423462867 --clippingRange 0.0 0.23307692423462867 --modulateRange 0.0 0.23076923191547394 \
        --gamma 0.0 --cmapResolution 256 --interpolation none --numSteps 150 --blendFactor 0.1 --smoothing 0 --resolution 100 --numInnerSteps 10 \
        --clipMode intersection --volume 0 \
        $mask_SN_L_warped --name "SN_L" --overlayType label --alpha 100.0 \
        --brightness 49.75000000000001 --contrast 49.90029860765409 --lut random --outline --outlineWidth 1 --volume 0 \
        $mask_SN_R_warped --name "SN_R" --overlayType label --alpha 100.0 \
        --brightness 49.75000000000001 --contrast 49.90029860765409 --lut random --outline --outlineWidth 1 --volume 0 \
        $mask_Manual_L_warped --name "maunal_L" --overlayType label --alpha 100.0 \
        --brightness 50 --contrast 50 --lut paul_tol_accessible --outlineWidth 0 --volume 0 \
        $mask_Auto_R_warped --name "auto_R" --overlayType label --alpha 100.0  \
        --brightness 50 --contrast 50 --lut paul_tol_accessible --outlineWidth 0 --volume 0
    fi


    done

  echo "done"
