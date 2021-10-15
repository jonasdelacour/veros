


subroutine momentum
!=======================================================================
! solve for momentum for taup1
!=======================================================================
 use main_module   
 use isoneutral_module   
 use timing_module   
 implicit none
 integer :: i,j,k

 !---------------------------------------------------------------------------------
 !  time tendency due to Coriolis force
 !---------------------------------------------------------------------------------
 do j=js_pe,je_pe
  do i=is_pe,ie_pe
   du_cor(i,j,:)= maskU(i,j,:)*(  coriolis_t(i  ,j)*(v(i  ,j,:,tau)+v(i  ,j-1,:,tau))*dxt(i  )/dxu(i)  &
                                 +coriolis_t(i+1,j)*(v(i+1,j,:,tau)+v(i+1,j-1,:,tau))*dxt(i+1)/dxu(i) )*0.25
   dv_cor(i,j,:)=-maskV(i,j,:)*(coriolis_t(i,j  )*(u(i-1,j  ,:,tau)+u(i,j  ,:,tau))*dyt(j  )*cost(j  )/( dyu(j)*cosu(j) )  &
                               +coriolis_t(i,j+1)*(u(i-1,j+1,:,tau)+u(i,j+1,:,tau))*dyt(j+1)*cost(j+1)/( dyu(j)*cosu(j) ) )*0.25
  enddo
 enddo

 !---------------------------------------------------------------------------------
 !  time tendency due to metric terms
 !---------------------------------------------------------------------------------
 if (coord_degree) then
  do j=js_pe,je_pe
   do i=is_pe,ie_pe
    du_cor(i,j,:) = du_cor(i,j,:) + maskU(i,j,:)*0.125*tantr(j)*( &
                      (u(i  ,j,:,tau)+u(i-1,j,:,tau))*(v(i  ,j,:,tau)+v(i  ,j-1,:,tau))*dxt(i  )/dxu(i) &
                    + (u(i+1,j,:,tau)+u(i  ,j,:,tau))*(v(i+1,j,:,tau)+v(i+1,j-1,:,tau))*dxt(i+1)/dxu(i) )
    dv_cor(i,j,:) = dv_cor(i,j,:) - maskV(i,j,:)*0.125*( &
                           tantr(j  )*(u(i,j  ,:,tau)+u(i-1,j  ,:,tau))**2*dyt(j  )*cost(j  )/( dyu(j)*cosu(j) ) &
                         + tantr(j+1)*(u(i,j+1,:,tau)+u(i-1,j+1,:,tau))**2*dyt(j+1)*cost(j+1)/( dyu(j)*cosu(j) ) )
   enddo
  enddo
 endif

 !---------------------------------------------------------------------------------
 ! non hydrostatic Coriolis terms, metric terms are neglected
 !---------------------------------------------------------------------------------
 if (.not. enable_hydrostatic) then
  do k=2,nz
   do i=is_pe,ie_pe
    du_cor(i,:,k) = du_cor(i,:,k) - maskU(i,:,k)*0.25*(coriolis_h(i  ,:)*area_t(i  ,:)*(w(i  ,:,k,tau)+w(i  ,:,k-1,tau)) &
                                                      +coriolis_h(i+1,:)*area_t(i+1,:)*(w(i+1,:,k,tau)+w(i+1,:,k-1,tau)) ) &
                                                        /area_u(i,:)
   enddo
  enddo
  k=1;
  do i=is_pe,ie_pe
   du_cor(i,:,k) = du_cor(i,:,k) - maskU(i,:,k)*0.25*(coriolis_h(i  ,:)*area_t(i  ,:)*(w(i  ,:,k,tau)) &
                                                     +coriolis_h(i+1,:)*area_t(i+1,:)*(w(i+1,:,k,tau)) )/area_u(i,:)
  enddo
  do k=1,nz-1
   do i=is_pe,ie_pe
    dw_cor(i,:,k) = maskW(i,:,k)*0.25*(coriolis_h(i,:)*dzt(k  )*(u(i,:,k  ,tau)+u(i-1,:,k  ,tau)) &
                                      +coriolis_h(i,:)*dzt(k+1)*(u(i,:,k+1,tau)+u(i-1,:,k+1,tau)) )/dzw(k)
   enddo
  enddo
 endif

 !---------------------------------------------------------------------------------
 ! transfer to time tendencies
 !---------------------------------------------------------------------------------
 do j=js_pe,je_pe
  do i=is_pe,ie_pe
   du(i,j,:,tau)=du_cor(i,j,:)
   dv(i,j,:,tau)=dv_cor(i,j,:)
  enddo
 enddo

 if (.not. enable_hydrostatic) then
  do j=js_pe,je_pe
   do i=is_pe,ie_pe
     dw(i,j,:,tau)=dw_cor(i,j,:)
   enddo
  enddo
 endif

 !---------------------------------------------------------------------------------
 ! wind stress forcing
 !---------------------------------------------------------------------------------
 do j=js_pe,je_pe
  do i=is_pe,ie_pe
   du(i,j,nz,tau)=du(i,j,nz,tau)+maskU(i,j,nz)*surface_taux(i,j)/dzt(nz)
   dv(i,j,nz,tau)=dv(i,j,nz,tau)+maskV(i,j,nz)*surface_tauy(i,j)/dzt(nz)
  enddo
 enddo

 !---------------------------------------------------------------------------------
 ! advection
 !---------------------------------------------------------------------------------
 call momentum_advection
 du(:,:,:,tau) = du(:,:,:,tau) + du_adv
 dv(:,:,:,tau) = dv(:,:,:,tau) + dv_adv
 if (.not. enable_hydrostatic) dw(:,:,:,tau) = dw(:,:,:,tau) + dw_adv

 call tic('fric')
 !---------------------------------------------------------------------------------
 ! vertical friction
 !---------------------------------------------------------------------------------
 K_diss_v = 0d0
 if (enable_implicit_vert_friction) call implicit_vert_friction
 if (enable_explicit_vert_friction) call explicit_vert_friction

 !---------------------------------------------------------------------------------
 ! TEM formalism for eddy-driven velocity
 !---------------------------------------------------------------------------------
 if (enable_TEM_friction) call isoneutral_friction

 !---------------------------------------------------------------------------------
 !horizontal friction
 !---------------------------------------------------------------------------------
 if (enable_hor_friction)        call harmonic_friction
 if (enable_biharmonic_friction) call biharmonic_friction

 !---------------------------------------------------------------------------------
 ! Rayleigh and bottom friction
 !---------------------------------------------------------------------------------
 K_diss_bot = 0d0
 if (enable_ray_friction)              call rayleigh_friction
 if (enable_bottom_friction)           call linear_bottom_friction
 if (enable_quadratic_bottom_friction) call quadratic_bottom_friction

 !---------------------------------------------------------------------------------
 ! add user defined forcing
 !---------------------------------------------------------------------------------
 if (enable_momentum_sources) call momentum_sources
 call toc('fric')

 !---------------------------------------------------------------------------------
 ! external mode
 !---------------------------------------------------------------------------------
 call tic('press')
 if (enable_streamfunction) then
  call solve_streamfunction
 else
  call solve_pressure
  if (itt==0) then 
       psi(:,:,tau)=psi(:,:,taup1)
       psi(:,:,taum1)=psi(:,:,taup1)
  endif
 endif
 if (.not. enable_hydrostatic) call solve_non_hydrostatic
 call toc('press')

end subroutine momentum




 
 subroutine vertical_velocity
!=======================================================================
!       vertical velocity from continuity : 
!       \int_0^z w_z dz =w(z)-w(0) = - \int dz (u_x +v_y)  
!        w(z)=-int dz u_x + v_y
!=======================================================================
    use main_module   
    implicit none
    integer :: i,j,k
    ! integrate from bottom to surface to see error in w
    k=1
    do j=js_pe-onx+1,je_pe+onx
     do i=is_pe-onx+1,ie_pe+onx
         w(i,j,k,taup1) =-maskW(i,j,k)*dzt(k)* &
               ((        u(i,j,k,taup1)-          u(i-1,j,k,taup1))/(cost(j)*dxt(i)) &
               +(cosu(j)*v(i,j,k,taup1)-cosu(j-1)*v(i,j-1,k,taup1))/(cost(j)*dyt(j)) )
     enddo
    enddo
    do k=2,nz
     do j=js_pe-onx+1,je_pe+onx
      do i=is_pe-onx+1,ie_pe+onx
          w(i,j,k,taup1) = w(i,j,k-1,taup1)-maskW(i,j,k)*dzt(k)* &
               ((        u(i,j,k,taup1)          -u(i-1,j,k,taup1))/(cost(j)*dxt(i)) &
               +(cosu(j)*v(i,j,k,taup1)-cosu(j-1)*v(i,j-1,k,taup1))/(cost(j)*dyt(j)) )
      enddo
     enddo
    enddo
end subroutine vertical_velocity




subroutine momentum_advection
!=======================================================================
! Advection of momentum with second order which is energy conserving
!=======================================================================
  use main_module   
  implicit none
  integer :: i,j,k
  real*8 :: utr(is_pe-onx:ie_pe+onx,js_pe-onx:je_pe+onx,nz)
  real*8 :: vtr(is_pe-onx:ie_pe+onx,js_pe-onx:je_pe+onx,nz)
  real*8 :: wtr(is_pe-onx:ie_pe+onx,js_pe-onx:je_pe+onx,nz)


 !---------------------------------------------------------------------------------
 !  Code from MITgcm
 !---------------------------------------------------------------------------------

!        uTrans(i,j) = u(i,j)*dyG(i,j)*drF(k)
!        vTrans(i,j) = v(i,j)*dxG(i,j)*drF(k)

!        fZon(i,j) = 0.25*( uTrans(i,j) + uTrans(i+1,j) ) *( u(i,j) + u(i+1,j) )
!        fMer(i,j) = 0.25*( vTrans(i,j) + vTrans(i-1,j) ) *( u(i,j) + u(i,j-1) )

!          gU(i,j,k,bi,bj) =  -
!     &     *( ( fZon(i,j  )  - fZon(i-1,j)  )
!     &       +( fMer(i,j+1)  - fMer(i,  j)  )
!     &       +( fVerUkp(i,j) - fVerUkm(i,j) )
!     &     ) /drF(k)   / rAw(i,j) 


!        fZon(i,j) = 0.25*( uTrans(i,j) + uTrans(i,j-1) )  *(v(i,j) + v(i-1,j) )
!        fMer(i,j) = 0.25*( vTrans(i,j) + vTrans(i,j+1) )  *(v(i,j) +  v(i,j+1) )

!          gV(i,j,k,bi,bj) =  -recip_drF(k)*recip_rAs(i,j,bi,bj)
!     &     *( ( fZon(i+1,j)  - fZon(i,j  )  )
!     &       +( fMer(i,  j)  - fMer(i,j-1)  )
!     &       +( fVerVkp(i,j) - fVerVkm(i,j) )
!     &     )


 do j=js_pe-onx,je_pe+onx
  do i=is_pe-onx,ie_pe+onx
    utr(i,j,:) = dzt(:)*dyt(j)*u(i,j,:,tau)*maskU(i,j,:)
    vtr(i,j,:) = dzt(:)*cosu(j)*dxt(i)*v(i,j,:,tau)*maskV(i,j,:)
    wtr(i,j,:) = area_t(i,j)*w(i,j,:,tau)*maskW(i,j,:)
  enddo
 enddo

 !---------------------------------------------------------------------------------
 ! for zonal momentum
 !---------------------------------------------------------------------------------
 do j=js_pe,je_pe
  do i=is_pe-1,ie_pe
    flux_east(i,j,:) = 0.25*(u(i,j,:,tau)+u(i+1,j,:,tau))*(utr(i+1,j,:)+utr(i,j,:))
  enddo
 enddo
 do j=js_pe-1,je_pe
  do i=is_pe,ie_pe
     flux_north(i,j,:) = 0.25*(u(i,j,:,tau)+u(i,j+1,:,tau))*(vtr(i+1,j,:)+vtr(i,j,:))
  enddo
 enddo
 do k=1,nz-1
  do j=js_pe,je_pe
   do i=is_pe,ie_pe
      flux_top(i,j,k) = 0.25*(u(i,j,k+1,tau)+u(i,j,k,tau))*(wtr(i,j,k)+wtr(i+1,j,k))
   enddo
  enddo
 enddo
 flux_top(:,:,nz)=0.0
 do j=js_pe,je_pe
  do i=is_pe,ie_pe
    du_adv(i,j,:) =  - maskU(i,j,:)*( flux_east(i,j,:) -flux_east(i-1,j,:) &
                                     +flux_north(i,j,:)-flux_north(i,j-1,:))/(area_u(i,j)*dzt(:))
  enddo
 enddo
 k=1; du_adv(:,:,k) = du_adv(:,:,k) - maskU(:,:,k)*flux_top(:,:,k)/(area_u(:,:)*dzt(k))
 do k=2,nz
     du_adv(:,:,k) = du_adv(:,:,k) - maskU(:,:,k)*(flux_top(:,:,k)-flux_top(:,:,k-1))/(area_u(:,:)*dzt(k))
 enddo
 !---------------------------------------------------------------------------------
 ! for meridional momentum
 !---------------------------------------------------------------------------------
 do j=js_pe,je_pe
  do i=is_pe-1,ie_pe
    flux_east(i,j,:) = 0.25*(v(i,j,:,tau)+v(i+1,j,:,tau))*(utr(i,j+1,:)+utr(i,j,:))
  enddo
 enddo
 do j=js_pe-1,je_pe
  do i=is_pe,ie_pe
     flux_north(i,j,:) = 0.25*(v(i,j,:,tau)+v(i,j+1,:,tau))*(vtr(i,j+1,:)+vtr(i,j,:))
  enddo
 enddo
 do k=1,nz-1
  do j=js_pe,je_pe
   do i=is_pe,ie_pe
      flux_top(i,j,k) = 0.25*(v(i,j,k+1,tau)+v(i,j,k,tau))*(wtr(i,j,k)+wtr(i,j+1,k))
   enddo
  enddo
 enddo
 flux_top(:,:,nz)=0.0
 do j=js_pe,je_pe
  do i=is_pe,ie_pe
    dv_adv(i,j,:) = - maskV(i,j,:)*( flux_east(i,j,:) -flux_east(i-1,j,:) &
                                    +flux_north(i,j,:)-flux_north(i,j-1,:))/(area_v(i,j)*dzt(:))
  enddo
 enddo
 k=1; dv_adv(:,:,k) = dv_adv(:,:,k) - maskV(:,:,k)*flux_top(:,:,k)/(area_v(:,:)*dzt(k))
 do k=2,nz
     dv_adv(:,:,k) = dv_adv(:,:,k) - maskV(:,:,k)*(flux_top(:,:,k)-flux_top(:,:,k-1))/(area_v(:,:)*dzt(k))
 enddo


 if (.not. enable_hydrostatic) then
  !---------------------------------------------------------------------------------
  ! for vertical momentum
  !---------------------------------------------------------------------------------
  do k=1,nz
   do j=js_pe,je_pe
    do i=is_pe-1,ie_pe
     flux_east(i,j,k) = 0.5*(w(i,j,k,tau)+w(i+1,j,k,tau))*(u(i,j,k,tau)+u(i,j,min(nz,k+1),tau))*0.5*maskW(i+1,j,k)*maskW(i,j,k)
    enddo
   enddo
  enddo
  do k=1,nz
   do j=js_pe-1,je_pe
    do i=is_pe,ie_pe
     flux_north(i,j,k) = 0.5*(w(i,j,k,tau)+w(i,j+1,k,tau))* & 
                         (v(i,j,k,tau)+v(i,j,min(nz,k+1),tau))*0.5*maskW(i,j+1,k)*maskW(i,j,k)*cosu(j)
    enddo
   enddo
  enddo
  do k=1,nz-1
   do j=js_pe,je_pe
    do i=is_pe,ie_pe
      flux_top(i,j,k) = 0.5*(w(i,j,k+1,tau)+w(i,j,k,tau))*(w(i,j,k,tau)+w(i,j,k+1,tau))*0.5*maskW(i,j,k+1)*maskW(i,j,k)
    enddo
   enddo
  enddo
  flux_top(:,:,nz)=0.0
  do j=js_pe,je_pe
   do i=is_pe,ie_pe
     dw_adv(i,j,:)=   maskW(i,j,:)* (-( flux_east(i,j,:)-  flux_east(i-1,j,:))/(cost(j)*dxt(i)) &
                                      -(flux_north(i,j,:)- flux_north(i,j-1,:))/(cost(j)*dyt(j)) )
   enddo
  enddo
  k=1; dw_adv(:,:,k) = dw_adv(:,:,k) - maskW(:,:,k)*flux_top(:,:,k)/dzw(k)
  do k=2,nz
     dw_adv(:,:,k) = dw_adv(:,:,k) - maskW(:,:,k)*(flux_top(:,:,k)-flux_top(:,:,k-1))/dzw(k)
  enddo
 endif

end subroutine momentum_advection
