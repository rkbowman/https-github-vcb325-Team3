

/*
Used proc SurveySelect to create sample data sets for exploration
using 0.1% of observations (100-300)
*/


proc surveyselect data=iaa.customer_transactions method=srs rate=0.001 out=iaa.sample_cust_info;
run;



/*****************************************************************
******************************************************************
*****************************************************************/



/*
Customer_info V2: concatenating name, reformatted ccnumber, split Vehicle, caluclated Age
				created numeric height variable and BMI
*/
proc sql;
	create table iaa.Customer_info_V2 as
	select Cust_ID, GivenName, MiddleInitial, Surname, catx(' ',GivenName, MiddleInitial, Surname) as Fullname 'Full Name' format=$25.,

		   StreetAddress, City, State, ZipCode, Country, TelephoneNumber, MothersMaiden, Birthday, int(('27jul2016'd-birthday)/365.25) as Age 'Age',

		   CCType, CCNumber format=16., CCExpires, NationalID, Vehicle, scan(vehicle,1, ' ') as VehicleYear 'Vehicle Year' format=$4.,
		   scan(vehicle, 2, ' ') as VehicleMake 'Vehicle Make' format=$15., scan(vehicle, 3, ' ') as VehicleModel 'Vehicle Model' format=$15., 

		   BloodType, Pounds, FeetInches, input(substr(feetinches,1,1),1.) as feet format=1., input(scan(feetinches,2, '%" '),2.) as inches format=2., 
		   calculated feet*12+calculated inches as height 'Height in Inches' format=2., 
		   (pounds*703)/(calculated height**2) as BMI 'BMI' format=4.1, gender, Race, Marriage
		   
	from iaa.Customer_info
	order by cust_id, age, surname;
quit;


proc means data=iaa.customer_info_v2 
nmiss n mean median std q1 q3 qrange range printalltypes maxdec=1;
	class gender;
	var age pounds height BMI;
run;

proc univariate data=iaa.customer_info_v2 ;
	var age pounds height BMI;
	histogram age / normal;
	histogram pounds / normal;
	histogram height / normal;
	histogram BMI / normal;
run;





/*****************************************************************
******************************************************************
*****************************************************************/




/*
Customer Family Medical V2: create indicator variables for each category Y=1, N=0
	
Create a table of variable names from the dictionary columns table and create 
	a column of indicator variables by concatenation.
	Place the name and indicator variables from the new table into  macro variables fmedvars and ind
	check that the macro variable is correct with a %put statement
	Finally update the Customer_Family_Medical table with the indicator variables in a data step
*/
proc sql;
	create table vars as
		select varnum, name, cat('I_',name) as Indicator
		from dictionary.columns
		where memname='SAMPLE_FAMILY_MED';
quit;

proc sql;
	select name
			into :fmedvars separated by ' '
	from vars
	where varnum ne 1;
	select indicator
			into  :ind separated by ' '
	from vars
	where varnum ne 1;
quit;

%put fmedvars is &fmedvars;
%put ind is &ind;


	
data iaa.Customer_Family_Medical_V2;
	set iaa.Customer_Family_Medical;
	array vars{34} $ &fmedvars;
	array ind{34}  &ind;
	do i=1 to dim(ind);
		if vars{i}='Y' then ind{i}=1;
		else ind{i} = 0;
	end;
	drop i;
	Total_Indications=sum(of I_Med:);

run;






/*****************************************************************
******************************************************************
*****************************************************************/






/*
Aduster Technician Table: group by cov_id, create new columns for adjuster and technician
							do the zipcodes match in all cases?
*/



proc sql;
create table coverage_id as
	select distinct cov_id
		from iaa.adjuster_technician
		order by cov_id;

create table adjuster as
	select   cov_id, 
			case substr(claim_info,1,1)
				when 'A' then Claim_info
				else 'None'
				end as Adjuster,
			case substr(claim_info,1,1)
				when 'A' then adj_zip
				else 'None'
				end as Adjuster_zip
			from iaa.adjuster_technician
			where calculated adjuster ne 'None'
			order by cov_id;
	
create table technician as
	select  cov_id, 
			case substr(claim_info,1,1)
				when 'T' then Claim_info
				else 'None'
				end as Technician,
			case substr(claim_info,1,1)
				when 'T' then adj_zip
				else 'None'
				end as Technician_zip
		from iaa.adjuster_technician
		where calculated technician ne 'None'
		order by cov_id;
create table iaa.adjuster_technician_v2 as
	select c.cov_id, adjuster, technician, 
		   adjuster_zip, technician_zip
		from coverage_id as c,
			 adjuster as a,
			 technician as t
		where c.cov_id=a.cov_id
			 and c.cov_id=t.cov_id
		order by cov_id;
	
quit;



/*Using SQL below, no rows were returned so adjuster/technician zips match*/
proc sql ;
	select adjuster_zip, technician_zip
		from iaa.adjuster_technician_v2
		where adjuster_zip ne technician_zip;
quit;


/*
report zipcodes bw customers and adjusters
*/


proc sql ;
	create table iaa.cust_adj_zip as
	select i.cust_id, put(zipcode,8.) as char_zip,  adjuster_zip, adjuster, ct.cov_id
		from iaa.customer_info_v2 as i,
			 iaa.adjuster_technician_v2 as at,
			 iaa.customer_transactions as ct
		where i.cust_id=ct.cust_id
			and ct.cov_id=at.cov_id
		order by adjuster;
quit;


/* Replace adjuster zip where missing with actual adjuster zip*/




/*****************************************************************
******************************************************************
*****************************************************************/



/*
Customer Transactions V2:  create formats
						   Most Transactions
						   proc freq for categories
						   Creation of indicator data set
*/








/*
Formats for Customer_Transaction Table
*/


proc format ;	
	value $trans 'IN'='Initial Coverage Started'
			     'CH' = 'Change in Coverage'
				 'CL' = 'Claim on Coverage'
				 'RE' = 'Coverage Rewarded'
				 ' ' = 'Missing'
				  other = 'Invalid';

	value $type 'T' = 'Term Life Insurance'
		        'W' = 'Whole Life Insurance'
				'V' = 'Variable Life Insurance'
				' ' = 'Missing'
				other = 'Invalid';

	value rewardr 100-<200 = 'Accidental Death'
		          200-<300 = 'Criminal Acts'
				  300-<500 = 'Health Related Causes'
				  500-<550 = 'Dangerous Activity - Exclusion'
				  550-<560 = 'War - Exclusion'
				  560-<570 = 'Aviation - Exclusion'
				  570-<580 = 'Suicide - Exclusion'
				  . = '. '
				  other = 'Invalid';
run;



/*
Most Transactions
*/


proc sql outobs=10;
	select cust_id, count(*) as Num_Transactions
		from iaa.customer_transactions
		group by cust_id
		order by Num_Transactions desc;
quit;

/*
Exploration of Transaction, Type, Reward_R using Proc Freq
*/

proc freq data=iaa.customer_transactions nlevels;
	tables transaction type reward_r;
	format transaction $trans. type $type. reward_r rewardr.;
run;


/*
Creation of customer_transaction_indicator data set
*/



data iaa.customer_transactions_indicator;
	set iaa.customer_transactions;
	select (transaction);
		when ('IN')  initial_trans=1;
		when ('CH')  change_trans=1;
		when ('CL')  claim_trans=1;
		when ('RE')  reward_trans=1;
		otherwise;
	end;
	select (type);
		when ('T')  term_type=1;
		when ('W')  whole_type=1;
		when ('V')  variable_type=1;
		otherwise;
	end;

	if 100<=reward_r<=199 then acc_reward=1;
	else if 200<=reward_r<=299 then crim_reward=1;
	else if 300<=reward_r<=499 then health_reward=1;
	else if 500<=reward_r<=549 then dan_ex_reward=1;
	else if 550<=reward_r<=559 then war_ex_reward=1;
	else if 560<=reward_r<=569 then av_ex_reward=1;
	else if 570<=reward_r<=579 then s_ex_reward=1;
	else if reward_r=. then miss_reward=1;
run;


/*
Need a total transactions column 
above and increase complexity with adding transaction number columns - 
transaction1 : tran1 type1 date1, etc? 
*/
