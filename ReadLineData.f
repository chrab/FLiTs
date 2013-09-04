	subroutine ReadLineData()
	use GlobalSetup
	use Constants
	IMPLICIT NONE
	integer i,j,i_low,i_up,imol,maxlevels
	
	allocate(Mol(nmol))

	do imol=1,nmol
		open(unit=80,file=linefile(imol),RECL=6000)
		read(80,*)
		read(80,*) Mol(imol)%name
		read(80,*)
		read(80,*) Mol(imol)%M
		read(80,*)
		read(80,*) Mol(imol)%nlevels
		read(80,*)
		allocate(Mol(imol)%E(Mol(imol)%nlevels))
		allocate(Mol(imol)%g(Mol(imol)%nlevels))
		do i=1,Mol(imol)%nlevels
			read(80,*) j,Mol(imol)%E(i),Mol(imol)%g(i)
		enddo
		read(80,*)
		read(80,*) Mol(imol)%nlines
		read(80,*)
		allocate(Mol(imol)%L(Mol(imol)%nlines))
		do i=1,Mol(imol)%nlines
			read(80,*) j,Mol(imol)%L(i)%jup,Mol(imol)%L(i)%jlow,Mol(imol)%L(i)%Aul,
     &				Mol(imol)%L(i)%freq,Mol(imol)%E(Mol(imol)%L(i)%jup)	!Mol%L(i)%Eup
			Mol(imol)%L(i)%freq=Mol(imol)%L(i)%freq*1d9
			Mol(imol)%L(i)%lam=clight*1d4/(Mol(imol)%L(i)%freq)
			Mol(imol)%L(i)%imol=imol

			i_low=Mol(imol)%L(i)%jlow
			i_up=Mol(imol)%L(i)%jup
			Mol(imol)%L(i)%Bul=Mol(imol)%L(i)%Aul/(2d0*hplanck*Mol(imol)%L(i)%freq**3/clight**2)
			Mol(imol)%L(i)%Blu=Mol(imol)%L(i)%Bul*Mol(imol)%g(i_up)/Mol(imol)%g(i_low)
		enddo
		close(unit=80)
	enddo

	maxlevels=0
	do imol=1,nmol
		if(Mol(imol)%nlevels.gt.maxlevels) maxlevels=Mol(imol)%nlevels
	enddo
	do i=0,nR
		do j=1,nTheta
			allocate(C(i,j)%npop(nmol,maxlevels))
			allocate(C(i,j)%abun(nmol))
			allocate(C(i,j)%line_width(nmol))
		enddo
	enddo

	if(popfile.ne.' ') 	call ReadPopData()

	if(LTE.or.popfile.eq.' ') call ComputeLTE()
	
	do i=0,nR
		do j=1,nTheta
			do imol=1,nmol
c				if(popfile.eq.' ') then
					C(i,j)%line_width(imol)=sqrt(2d0*kb*C(i,j)%Tgas/(mp*Mol(imol)%M))
c					C(i,j)%line_width(imol)=C(i,j)%line_width(imol)+
c     &					0.5d0*sqrt((7.0/5.0)*kb*C(i,j)%Tgas/(mp*2.3))
c				endif
				if(C(i,j)%line_width(imol).lt.vresolution/vres_mult) C(i,j)%line_width(imol)=vresolution/vres_mult
			enddo
		enddo
	enddo
	
	return
	end
	
	
	
c=========================================================================================
c This subroutine reads in a forMCFOST.fits type of file generated by ProDiMo
c It fills the population levels
c=========================================================================================
	subroutine ReadPopData()
	use GlobalSetup
	use Constants
	IMPLICIT NONE
	integer nvars,ivars,i,j,l,k,naxis,npopname,imol,ipop(nmol),ihdu
	character*7 vars(10),hdu
	real,allocatable :: array(:,:,:,:)
	real*8,allocatable :: array_d(:,:,:,:)
	integer*4 :: status,stat2,stat3,readwrite,unit,blocksize,nfound,group
	integer*4 :: firstpix,nbuffer,npixels,hdunum,hdutype,ix,iz,ilam
	integer*4 :: istat,stat4,tmp_int,stat5,stat6
	real  :: nullval
	real*8  :: nullval_d,tot
	logical*4 :: anynull
	integer*4, dimension(4) :: naxes
	character*80 comment,errmessage
	character*30 errtext,popname(20)

	! Get an unused Logical Unit Number to use to open the FITS file.
	status=0

	call ftgiou (unit,status)
	! Open file
	readwrite=0
	call ftopen(unit,popfile,readwrite,blocksize,status)
	if (status /= 0) then
		call output("Population file not found "//trim(popfile))
		call output("==================================================================")
		stop
	endif
	group=1
	firstpix=1
	nullval=-999
	nullval_d=-999

	call output("Reading level populations from: "//trim(popfile))

c set default names of the species
	popname(1) = "C+"
	popname(2) = "O"
	popname(3) = "CO"
	popname(4) = "o-H2O"
	popname(5) = "p-H2O"
	npopname=5

	do i=1,npopname
		do imol=1,nmol
			if(trim(Mol(imol)%name).eq.trim(popname(i))) ipop(imol)=i
		enddo
	enddo

	!------------------------------------------------------------------------
	! HDU0 : grid
	!------------------------------------------------------------------------
	! Skip this, it is already done

	!------------------------------------------------------------------------------
	! HDU 2: Gas Temperature 
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=2

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nR
		do j=1,nTheta
			C(i,j)%Tgas=array_d(i,nTheta+1-j,1,1)
		enddo
	enddo

	deallocate(array_d)
	
	!------------------------------------------------------------------------------
	! HDU 3 : Molecular particle densities [1/cm^3]
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=3

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nR
		do j=1,nTheta
			if(C(i,j)%dens.gt.1d-50) then
				do imol=1,nmol
					C(i,j)%abun(imol)=array_d(ipop(imol),i,nTheta+1-j,1)*Mol(imol)%M*mp/C(i,j)%dens
				enddo
			else
				C(i,j)%abun=1d-4
			endif
		enddo
	enddo

	deallocate(array_d)

	!------------------------------------------------------------------------------
	! HDU 4 : Line broadening parameter
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=3

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nR
		do j=1,nTheta
			do imol=1,nmol
				C(i,j)%line_width(imol)=array_d(ipop(imol),i,nTheta+1-j,1)*1d5
			enddo
		enddo
	enddo

	deallocate(array_d)
	
	!------------------------------------------------------------------------------
	! HDU 5... : level populations
	!------------------------------------------------------------------------------

	ihdu=1
2	continue
	
	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	do imol=1,nmol
		if(ipop(imol).eq.ihdu) exit
	enddo
	if(imol.gt.nmol) goto 2	

	naxis=3

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpve(unit,group,firstpix,npixels,nullval,array,anynull,status)

	if(naxes(1).lt.Mol(imol)%nlevels.and..not.LTE) then
		call output("For species: " //trim(Mol(imol)%name))
		call output("Assuming levels above " // int2string(naxes(1),'(i4)') // "unpopulated")
	endif

	if(naxes(1).gt.Mol(imol)%nlevels) naxes(1)=Mol(imol)%nlevels
	do i=1,nR
		do j=1,nTheta
			C(i,j)%npop(imol,1:Mol(imol)%nlevels)=0d0
			tot=0d0
			do k=1,naxes(1)
				C(i,j)%npop(imol,k)=array(k,i,nTheta+1-j,1)
			enddo
			do k=2,naxes(1)
				C(i,j)%npop(imol,k)=C(i,j)%npop(imol,k-1)*C(i,j)%npop(imol,k)
			enddo
			C(i,j)%npop(imol,1)=1d0-sum(C(i,j)%npop(imol,2:naxes(1)))
		enddo
	enddo

	deallocate(array)

	ihdu=ihdu+1

	goto 2

1	continue

	!  Close the file and free the unit number.
	call ftclos(unit, status)
	call ftfiou(unit, status)

	!  Check for any error, and if so print out error messages
	!  Get the text string which describes the error
	if (status > 0) then
	   call ftgerr(status,errtext)
	   print *,'FITSIO Error Status =',status,': ',errtext

	   !  Read and print out all the error messages on the FITSIO stack
	   call ftgmsg(errmessage)
	   do while (errmessage .ne. ' ')
		  print *,errmessage
		  call ftgmsg(errmessage)
	   end do
	endif

	do j=1,nTheta
		do imol=1,nmol
			C(0,j)%npop(imol,1:Mol(imol)%nlevels)=C(1,j)%npop(imol,1:Mol(imol)%nlevels)
			C(0,j)%abun(imol)=C(1,j)%abun(imol)
		enddo
	enddo
	
	return
	end
	


