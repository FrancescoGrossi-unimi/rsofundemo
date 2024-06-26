library(dplyr)
library(tidyr)
library(rsofun)
library(here)
library(cwd)
library(FluxDataKit)

# We use `rsofun_driver_data_v3.rds`, provided on Zenodo and whc 2m
# driver data can be found on [Zenodo](https://zenodo.org/records/10885934)
# Download that files and specify its local path
cost_whc_driver <- var_whc_driver <- readRDS(here("data","rsofun_driver_data_v3.rds")) #insert your local path

# filter by land use (remove crop and wetland)
keep <- fdk_site_info|>
  filter(igbp_land_use != "CRO" & igbp_land_use != "WET")

cost_whc_driver <- cost_whc_driver[which(cost_whc_driver$sitename %in% keep$sitename),]
var_whc_driver <- var_whc_driver[which(var_whc_driver$sitename %in% keep$sitename),]

# filter by good quality le_corr
keep <- fdk_site_fullyearsequence |>
  filter(drop_lecorr != TRUE)

cost_whc_driver <- cost_whc_driver[which(cost_whc_driver$sitename %in% keep$sitename),]
var_whc_driver <- var_whc_driver[which(var_whc_driver$sitename %in% keep$sitename),]


# function used to create dataframes
get_annual_aet_pet <- function(df){
  df |>
    mutate(year = lubridate::year(date)) |>
    group_by(year) |>
    summarise(aet = sum(aet),
              pet = sum(pet)) |>
    ungroup() |>
    summarise(aet = mean(aet),
              pet = mean(pet))
}

get_annual_prec_cond <- function(df){
  df |>
    mutate(year = lubridate::year(date)) |>
    group_by(year) |>
    summarise(prec_cond = sum(prec_cond)) |>
    ungroup() |>
    summarise(prec_cond = mean(prec_cond))
}

get_annual_gpp_netrad <-  function(df){
  df |>
    mutate(year = lubridate::year(date)) |>
    group_by(year) |>
    summarise(gpp = sum(gpp),
               netrad = sum(netrad)) |>
    ungroup() |>
    summarise(gpp = mean(gpp),
              netrad = mean(netrad))
}

transfrom_le_ET <-  function(df){
  df |>
    mutate(ET = convert_et(le,temp,patm))  |>
    mutate(year = lubridate::year(date)) |>
    group_by(year) |>
    summarise(ET = sum(ET)) |>
    ungroup() |>
    summarise(ET = mean(ET))
}


# paramter for p model
params_modl <- list(
  kphio              = 0.04998,
  kphio_par_a        = 0.0,
  kphio_par_b        = 1.0,
  soilm_thetastar    = 0.6 * 240,
  soilm_betao        = 0.0,
  beta_unitcostratio = 146.0,
  rd_to_vcmax        = 0.014,
  tau_acclim         = 30.0,
  kc_jmax            = 0.41
)

# change whc to previous result
csv_2m = read.csv(here("data","whc_2m.csv"),sep=" ")

# check if the sites in csv_2m and cost_whc_driver matches
all(cost_whc_driver$sitename == csv_2m$sitename)

for(i in 1:dim(cost_whc_driver)[1]){
  cost_whc_driver$site_info[i][[1]][4] <- csv_2m$WHC[i]
}

# run p model

cost_whc_output <- rsofun::runread_pmodel_f(
  cost_whc_driver,
  par = params_modl
)

# some simulations failed due to missing values in the forcing. If that happens,
# the number of rows in the output data is 1.
cost_whc_output <- cost_whc_output |>
  mutate(len = purrr::map_int(data, ~nrow(.))) |>
  filter(len != 1) |>
  select(-len)

# create dataframe
cost_whc_adf <- cost_whc_output |>
  mutate(cost_whc_adf = purrr::map(data, ~get_annual_aet_pet(.))) |>
  unnest(cost_whc_adf) |>
  select(sitename, aet,pet)

cost_whc_adf <- cost_whc_driver |>
  unnest(forcing) |>
  left_join(
    cost_whc_output |>
      unnest(data) |>
      select(-snow, -netrad, -fapar, gpp_pmodel = gpp),
    by = c("sitename", "date")
  ) |>
  mutate(prec = (rain + snow) * 60 * 60 * 24) |>
  mutate(prec_cond = prec + cond) |>
  group_by(sitename) |>
  nest() |>
  mutate(df = purrr::map(data, ~get_annual_prec_cond(.))) |>
  unnest(df) |>
  select(sitename, prec_cond) |>
  right_join(
    cost_whc_adf,
    by = "sitename"
  )

whc <-  cost_whc_output |>
  unnest(site_info) |>
  select(whc)

cost_whc_adf <- cost_whc_output |>
  mutate(df = purrr::map(data, ~get_annual_gpp_netrad(.))) |>
  unnest(df) |>
  select(sitename,gpp,netrad) |>
  right_join(
    cost_whc_adf,
    by = "sitename"
  )

cost_whc_adf <- cost_whc_driver |>
  mutate(df = purrr::map(forcing, ~transfrom_le_ET(.))) |>
  unnest(df) |>
  select(sitename,ET) |>
  right_join(
    cost_whc_adf,
    by = "sitename"
  )

whc <-  cost_whc_output |>
  unnest(site_info) |>
  select(whc)

cost_whc_adf$whc <- whc[[1]]

# run p model
var_whc_output <- rsofun::runread_pmodel_f(
  var_whc_driver,
  par = params_modl
)

# some simulations failed due to missing values in the forcing. If that happens,
# the number of rows in the output data is 1.
var_whc_output <- var_whc_output |>
  mutate(len = purrr::map_int(data, ~nrow(.))) |>
  filter(len != 1) |>
  select(-len)

# create dataframe
var_whc_adf <- var_whc_output |>
  mutate(var_whc_adf = purrr::map(data, ~get_annual_aet_pet(.))) |>
  unnest(var_whc_adf) |>
  select(sitename, aet, pet)

var_whc_adf <- var_whc_driver |>
  unnest(forcing) |>
  left_join(
    var_whc_output |>
      unnest(data) |>
      select(-snow, -netrad, -fapar, gpp_pmodel = gpp),
    by = c("sitename", "date")
  ) |>
  mutate(prec = (rain + snow) * 60 * 60 * 24) |>
  mutate(prec_cond = prec + cond) |>
  group_by(sitename) |>
  nest() |>
  mutate(df = purrr::map(data, ~get_annual_prec_cond(.))) |>
  unnest(df) |>
  select(sitename, prec_cond) |>
  right_join(
    var_whc_adf,
    by = "sitename"
  )

whc <-  var_whc_output |>
  unnest(site_info) |>
  select(whc)

var_whc_adf$whc <- whc[[1]]

var_whc_adf <- var_whc_output |>
  mutate(df = purrr::map(data, ~get_annual_gpp_netrad(.))) |>
  unnest(df) |>
  select(sitename,gpp,netrad) |>
  right_join(
    var_whc_adf,
    by = "sitename"
  )

var_whc_adf <- var_whc_driver |>
  mutate(df = purrr::map(forcing, ~transfrom_le_ET(.))) |>
  unnest(df) |>
  select(sitename,ET) |>
  right_join(
    var_whc_adf,
    by = "sitename"
  )

saveRDS(cost_whc_adf,here("data","output_costant_whc.rds"))
saveRDS(var_whc_adf,here("data","output_variable_whc.rds"))
