c=========================================================================================
c This subroutine reads in a forFLiTs.fits file generated by ProDiMo
c It fills the arrays:
c dens,T,kabs,kext,ksca,v,lam_cont,R,Theta,Fstar,and the population levels
c=========================================================================================
	subroutine ReadForFLiTs()
	use GlobalSetup
	use Constants
	IMPLICIT NONE
	integer nvars,ivars,i,j,k,imol,l,naxis
	character*7 vars(10),hdu
	real,allocatable :: array(:,:,:,:)
	real*8,allocatable :: array_d(:,:,:,:)
	integer*4 :: status,stat2,stat3,readwrite,unit,blocksize,nfound,group
	integer*4 :: firstpix,nbuffer,npixels,hdunum,hdutype,ix,iz,ilam
	integer*4 :: istat,stat4,tmp_int,stat5,stat6
	real  :: nullval
	real*8  :: nullval_d,xx,zz,rr,tot
	logical*4 :: anynull
	integer*4, dimension(4) :: naxes
	character*80 comment,errmessage
	character*30 errtext

	! Get an unused Logical Unit Number to use to open the FITS file.
	status=0

	call ftgiou (unit,status)
	! Open file
	readwrite=0
	call ftopen(unit,FLiTsfile,readwrite,blocksize,status)
	if (status /= 0) then
		write(*,'("forFLiTs file not found")')
		write(9,'("forFLiTs file not found")')
		print*,trim(FLiTsfile)
		write(*,'("--------------------------------------------------------")')
		write(9,'("--------------------------------------------------------")')
		stop
	endif
	group=1
	firstpix=1
	nullval=-999
	nullval_d=-999


	!------------------------------------------------------------------------
	! HDU0 : grid
	!------------------------------------------------------------------------
	! Check dimensions
	call ftgknj(unit,'NAXIS',1,3,naxes,nfound,status)

	npixels=naxes(1)*naxes(2)*naxes(3)

	! Read model info

	call ftgkyd(unit,'Rin',Rin,comment,status)
	call ftgkyd(unit,'Rout',Rout,comment,status)

	call ftgkyd(unit,'Mstar',Mstar,comment,status)
	call ftgkyd(unit,'Rstar',Rstar,comment,status)

	call ftgkyd(unit,'distance',distance,comment,status)

	call ftgkyj(unit,'NXX',nR,comment,status)
	nR=nR+1
	call ftgkyj(unit,'NZZ',nTheta,comment,status)

	call ftgkyj(unit,'NSPEC',nspec,comment,status)
	
	allocate(C(0:nR,0:nTheta))
	allocate(R(0:nR+1))
	allocate(Theta(0:nTheta+1))

	! read_image
	allocate(array(nR-1,nTheta,4,1))
	allocate(R_av(0:nR))
	allocate(theta_av(0:nTheta))

	call ftgpve(unit,group,firstpix,npixels,nullval,array,anynull,status)

	Rin=array(1,1,1,1)/AU
	call output("Adjusting Rin to:  "//trim(dbl2string(Rin,'(f8.3)')) //" AU")
	Rout=array(nR-1,1,2,1)/AU
	call output("Adjusting Rout to: "//trim(dbl2string(Rout,'(f8.3)')) //" AU")

	R(0)=Rstar*Rsun
	do i=1,nR-1
		R(i)=array(i,1,1,1)
	enddo
	R(nR)=array(nR-1,1,2,1)

	do i=1,nR-1
		R_av(i)=sqrt(R(i)*R(i+1))
	enddo

c in the theta grid we actually store cos(theta) for convenience
	Theta(0)=1d0
	do j=1,nTheta
		Theta(j)=array(1,nTheta+1-j,4,1)/R_av(1)
	enddo
	Theta(nTheta+1)=0d0

	if(cylindrical) then
		theta_av(0)=acos(Theta(1))/2d0
	else
		Theta(1)=1d0
		theta_av(0)=0d0
	endif

	do j=1,nTheta
		theta_av(j)=acos((Theta(j)+Theta(j+1))/2d0)
	enddo

	if(cylindrical) then
		if(Theta(1).lt.1d0) then
			Rout=Rout*1.0001/sin(acos(Theta(1)))
		else
			call output("Grid seems to be spherical")
			call output("SWITCHING TO SPHERICAL GRID")
			cylindrical=.false.
			Rout=Rout*1.0001
		endif
	else
		Rout=Rout*1.0001
	endif

	R(nR+1)=Rout*AU

	R_av(nR-1)=sqrt(R(nR-1)*R(nR))
	R_av(nR)=sqrt(R(nR)*R(nR+1))

	call sort(R(1:nR+1),nR+1)

	allocate(R_sphere(0:nR+1))
	allocate(R_av_sphere(0:nR+1))
	if(cylindrical) then
		do i=0,nR
			R_sphere(i)=R(i)/sin(acos(Theta(1)))
			R_av_sphere(i)=R_av(i)/sin(acos(Theta(1)))
		enddo
		R_sphere(nR+1)=R(nR+1)
		R_av_sphere(nR)=sqrt(R_sphere(nR)*R_sphere(nR+1))
	else
		do i=0,nR
			R_sphere(i)=R(i)
			R_av_sphere(i)=R_av(i)
		enddo
		R_sphere(nR+1)=R(nR+1)
	endif

	deallocate(array)

	do i=0,nR
		do j=0,nTheta
			allocate(C(i,j)%npop0(nspec))
			allocate(C(i,j)%N0(nspec))
			allocate(C(i,j)%line_width0(nspec))
		enddo
	enddo

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

	do i=1,nR-1
		do j=1,nTheta
			C(i,j)%Tgas=array_d(i,nTheta+1-j,1,1)
			if(C(i,j)%Tgas.lt.1d0) C(i,j)%Tgas=1d0
		enddo
	enddo

	deallocate(array_d)

	!------------------------------------------------------------------------------
	! HDU 3: Dust Temperature 
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

	do i=1,nR-1
		do j=1,nTheta
			C(i,j)%Tdust=array_d(i,nTheta+1-j,1,1)
			if(C(i,j)%Tdust.lt.1d0) C(i,j)%Tdust=1d0
		enddo
	enddo

	deallocate(array_d)


	!------------------------------------------------------------------------------
	! HDU 4 : Gas density [1/cm^3]
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

	do i=1,nR-1
		do j=1,nTheta
			C(i,j)%dens=array_d(i,nTheta+1-j,1,1)*mp
			if(C(i,j)%dens.lt.1d-50) C(i,j)%dens=1d-60
		enddo
	enddo

	deallocate(array_d)


	!------------------------------------------------------------------------------
	! HDU 5 : Lambda
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=1

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	nlam_star=naxes(1)
 	allocate(lam_star(nlam_star))
 	allocate(FstarHR(nlam_star))
 
	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nlam_star
		lam_star(i)=array_d(i,1,1,1)*1d4
	enddo

	deallocate(array_d)

	!------------------------------------------------------------------------------
	! HDU 6 : Star spectrum
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=1

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nlam_star
		FstarHR(i)=array_d(i,1,1,1)
	enddo

	deallocate(array_d)

	!------------------------------------------------------------------------------
	! HDU 7 : Lambda
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=1

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	nlam=naxes(1)
	do i=0,nR
		do j=0,nTheta
			allocate(C(i,j)%kabs(nlam))
			allocate(C(i,j)%albedo(nlam))
			allocate(C(i,j)%kext(nlam))
			allocate(C(i,j)%LRF(nlam))
		enddo
	enddo
 	allocate(lam_cont(nlam))
 	allocate(Fstar(nlam))
 
	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nlam
		lam_cont(i)=array_d(i,1,1,1)*1d4
	enddo

	deallocate(array_d)


	!------------------------------------------------------------------------------
	! HDU 8 : Opacites (abs)
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=4

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nR-1
		do j=1,nTheta
			do l=1,nlam
				C(i,j)%kabs(l)=0d0	!array_d(l,i,nTheta+1-j,1)
			enddo
		enddo
	enddo

	deallocate(array_d)


	!------------------------------------------------------------------------------
	! HDU 9 : Opacites (ext)
	!------------------------------------------------------------------------------

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=4

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array_d(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpvd(unit,group,firstpix,npixels,nullval_d,array_d,anynull,status)

	do i=1,nR-1
		do j=1,nTheta
			do l=1,nlam
				C(i,j)%kext(l)=0d0	!array_d(l,i,nTheta+1-j,1)
				if(C(i,j)%kext(l).gt.1d-150) then
					C(i,j)%albedo(l)=(C(i,j)%kext(l)-C(i,j)%kabs(l))/C(i,j)%kext(l)
				else
					C(i,j)%albedo=0.5d0
				endif
			enddo
		enddo
	enddo

	deallocate(array_d)

	!------------------------------------------------------------------------------
	! HDU 10 : Internal field
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

	do i=1,nR-1
		do j=1,nTheta
			do l=1,nlam
				C(i,j)%LRF(l)=array_d(l,i,nTheta+1-j,1)
c				C(i,j)%LRF(l)=C(i,j)%LRF(l)*lam_cont(l)*1d3*1d-4/clight
			enddo
		enddo
	enddo

	deallocate(array_d)


	!------------------------------------------------------------------------------
	! HDU 11 : Molecular particle densities [1/cm^3]
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

	do i=1,nR-1
		do j=1,nTheta
			do imol=1,nspec
				C(i,j)%N0(imol)=array_d(imol,i,nTheta+1-j,1)
			enddo
		enddo
	enddo

	deallocate(array_d)

	!------------------------------------------------------------------------------
	! HDU 12 : Line broadening parameter
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

	do i=1,nR-1
		do j=1,nTheta
			do imol=1,nspec
				C(i,j)%line_width0(imol)=array_d(imol,i,nTheta+1-j,1)
			enddo
		enddo
	enddo

	deallocate(array_d)
	
	!------------------------------------------------------------------------------
	! HDU 13... : relative level populations
	!------------------------------------------------------------------------------

	allocate(mol_name0(nspec))
	allocate(npop0(nspec))
	
	do imol=1,nspec

	!  move to next hdu
	call ftmrhd(unit,1,hdutype,status)
	if(status.ne.0) then
		status=0
		goto 1
	endif

	naxis=3

	! Check dimensions
	call ftgknj(unit,'NAXIS',1,naxis,naxes,nfound,status)

	call ftgkyj(unit,'NLEV',npop0(imol),comment,status)
	call ftgkys(unit,'SPECIES',mol_name0(imol),comment,status)

	do i=0,nR
		do j=0,nTheta
			allocate(C(i,j)%npop0(imol)%N(npop0(imol)))
		enddo
	enddo
	
	do i=naxis+1,4
		naxes(i)=1
	enddo
	npixels=naxes(1)*naxes(2)*naxes(3)*naxes(4)

	! read_image
	allocate(array(naxes(1),naxes(2),naxes(3),naxes(4)))

	call ftgpve(unit,group,firstpix,npixels,nullval,array,anynull,status)

	do i=1,nR-1
		do j=1,nTheta
			C(i,j)%npop0(imol)%N=0d0
			do k=1,naxes(1)
				C(i,j)%npop0(imol)%N(k)=array(k,i,nTheta+1-j,1)
			enddo
c			do k=2,naxes(1)
c				C(i,j)%npop0(imol)%N(k)=C(i,j)%npop0(imol)%N(k-1)*C(i,j)%npop0(imol)%N(k)
c			enddo
c			tot=sum(C(i,j)%npop0(imol)%N(1:naxes(1)))
c			C(i,j)%npop0(imol)%N(1:naxes(1))=C(i,j)%npop0(imol)%N(1:naxes(1))/tot
		enddo
	enddo

	deallocate(array)

	enddo


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

	
	do i=1,nR-1
		do j=1,nTheta
c			C(i,j)%v=sqrt(G*Mstar*Msun*sin(theta_av(j))/R_av(i))
c			C(i,j)%v=sqrt(G*Mstar*Msun*sin(theta_av(j))**2/R_av(i))
			xx=R_av(i)
			zz=xx/tan(theta_av(j))
			rr=sqrt(xx*xx+zz*zz)
			C(i,j)%v=sqrt(G*Mstar*Msun*xx*xx/(rr*rr*rr))
		enddo
	enddo
	i=0
	do j=0,nTheta
		C(i,j)%kext(1:nlam)=1d-70
		C(i,j)%kabs(1:nlam)=1d-70
c		C(i,j)%v=sqrt(G*(Mstar*Msun)*sin(theta_av(j))/(sqrt(R_av(1)*Rstar*Rsun)))
c		C(i,j)%v=sqrt(G*Mstar*Msun*sin(theta_av(j))**2/(sqrt(R_av(1)*Rstar*Rsun)))
		xx=R_av(1)
		zz=xx/tan(theta_av(j))
		rr=sqrt(xx*xx+zz*zz)
		C(i,j)%v=sqrt(G*Mstar*Msun*xx*xx/(rr*rr*rr))
		C(i,j)%dens=1d-60
	enddo
	i=nR
	do j=0,nTheta
		C(i,j)%kext(1:nlam)=1d-70
		C(i,j)%kabs(1:nlam)=1d-70
c		C(i,j)%v=sqrt(G*(Mstar*Msun)*sin(theta_av(j))/(sqrt(R_av(1)*Rstar*Rsun)))
c		C(i,j)%v=sqrt(G*Mstar*Msun*sin(theta_av(j))**2/(sqrt(R_av(1)*Rstar*Rsun)))
		xx=R_av(i)
		zz=xx/tan(theta_av(j))
		rr=sqrt(xx*xx+zz*zz)
		C(i,j)%v=sqrt(G*Mstar*Msun*xx*xx/(rr*rr*rr))
		C(i,j)%dens=1d-60
	enddo

	j=0
	do i=1,nR
		C(i,j)%kext(1:nlam)=1d-70
		C(i,j)%kabs(1:nlam)=1d-70
c		C(i,j)%v=sqrt(G*(Mstar*Msun)*sin(theta_av(j))/(sqrt(R_av(1)*Rstar*Rsun)))
c		C(i,j)%v=sqrt(G*Mstar*Msun*sin(theta_av(j))**2/(sqrt(R_av(1)*Rstar*Rsun)))
		xx=R_av(i)
		zz=xx/tan(theta_av(j))
		rr=sqrt(xx*xx+zz*zz)
		C(i,j)%v=sqrt(G*Mstar*Msun*xx*xx/(rr*rr*rr))
		C(i,j)%dens=1d-60
	enddo
	
	return
	end
	

