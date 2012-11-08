module CalcLike
 use CMB_Cls
 use cmbtypes
 use Random
 use settings
 use ParamDef
 use Likelihood
 use DataLikelihoodList
 implicit none

 real :: Temperature  = 1

 logical changeMask(num_params)
 logical SlowChanged, PowerChanged

contains

  function GenericLikelihoodFunction(Params) 
    type(ParamSet)  Params 
    real :: GenericLikelihoodFunction
   
  
   !Used when you want to plug in your own CMB-independent likelihood function:
   !set generic_mcmc=.true. in settings.f90, then write function here returning -Ln(Likelihood)
   !Parameter array is Params%P
    !!!!
   ! GenericLikelihoodFunction = greatLike(Params%P)
   ! GenericLikelihoodFunction = LogZero 
    call MpiStop('GenericLikelihoodFunction: need to write this function!')
    GenericLikelihoodFunction=0

  end function GenericLikelihoodFunction

  
  function TestHardPriors(CMB, Info) 
    real TestHardPriors
    Type (CMBParams) CMB
    Type(ParamSetInfo) Info

    TestHardPriors = logZero
 
    if (.not. generic_mcmc) then
     if (CMB%H0 < H0_min .or. CMB%H0 > H0_max) return
     if (CMB%zre < Use_min_zre) return

    end if
    TestHardPriors = 0
 
  end function TestHardPriors

  function GetLogLike(Params) !Get -Ln(Likelihood) for chains
    type(ParamSet)  Params 
    Type (CMBParams) CMB
    real GetLogLike
    logical, save:: first=.true.

    if (any(Params%P > Scales%PMax) .or. any(Params%P < Scales%PMin)) then
       GetLogLike = logZero
       return
    end if

    if (generic_mcmc) then
        GetLogLike = GenericLikelihoodFunction(Params) 
        if (GetLogLike /= LogZero) GetLogLike = GetLogLike + getLogPriors(Params%P)
        if (GetLogLike /= LogZero) GetLogLike = GetLogLike/Temperature
    else
      GetLogLike  = TestHardPriors(CMB, Params%Info)
      if (GetLogLike == logZero) return
      call ParamsToCMBParams(Params%P,CMB)
      if (first) then
           changeMask = .true.
           first = .false.
      else
           changeMask = Params%Info%lastParamArray/=Params%P
      end if

     if (CalculateRequiredTheoryChanges(CMB, Params)) then
       GetLogLike = GetLogLikeWithTheorySet(CMB, Params)
     else
       GetLogLike = logZero
     end if

     if (GetLogLike/=logZero) Params%Info%lastParamArray = Params%P
    end if 

  end function GetLogLike

  function GetLogLikePost(CMB, P, Info)
  !for importance sampling where theory may be pre-stored
    real GetLogLikePost
    Type (CMBParams) CMB
    Type(ParamSetInfo) Info
    real P(num_params)
    
    GetLogLikePost=logZero
   
    !need to init background correctly if new BAO etc

  end function GetLogLikePost
  
  function getLogPriors(P) result(logLike)
  integer i
  real, intent(in) :: P(num_params)
  real logLike
  
  logLike=0
  do i=1,num_params
        if (Scales%PWidth(i)/=0 .and. GaussPriors%std(i)/=0) then
          logLike = logLike + ((P(i)-GaussPriors%mean(i))/GaussPriors%std(i))**2
        end if
  end do
  logLike=logLike/2

  end function getLogPriors
  
  logical function CalculateRequiredTheoryChanges(CMB, Params)
    type(ParamSet)  Params 
    type (CMBParams) CMB
    integer error

     SlowChanged = any(changeMask(1:num_hard))
     PowerChanged = any(changeMask(index_initpower:index_initpower+num_initpower-1))
     error=0
     if (Use_CMB .or. Use_LSS) then
         if (SlowChanged) then
           call GetNewTransferData(CMB, Params%Info, error)
         end if
         if (SlowChanged .or. PowerChanged .and. error==0) then
           call GetNewPowerData(CMB, Params%Info, error)
         end if
     end if
   CalculateRequiredTheoryChanges = error==0

  end function CalculateRequiredTheoryChanges

  
  function GetLogLikeWithTheorySet(CMB, Params) result(logLike)
    real logLike
    Type (CMBParams) CMB
    Type(ParamSet) Params
    integer error
    real itemLike
    Class(DataLikelihood), pointer :: like
    integer i
    logical backgroundSet
    
    backgroundSet = slowChanged
    logLike = logZero

    do i= 1, DataLikelihoods%count
     like => DataLikelihoods%Item(i)
     if (any(like%dependent_params .and. changeMask )) then
          if (like%needs_background_functions .and. .not. backgroundSet) then
              call SetTheoryForBackground(CMB)
              backgroundSet = .true.
          end if
          itemLike = like%LogLike(CMB, Params%Info%Theory)
          if (itemLike == logZero) return
          Params%Info%Likelihoods(i) = itemLike
     end if
    end do
    logLike = sum(Params%Info%likelihoods(1:DataLikelihoods%Count))
    logLike = logLike + getLogPriors(Params%P)
    logLike = logLike/Temperature

  end function GetLogLikeWithTheorySet


end module CalcLike
